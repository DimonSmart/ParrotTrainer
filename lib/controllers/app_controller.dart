import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/app_language.dart';
import '../models/activity_history.dart';
import '../models/training_settings.dart';
import '../models/training_statistics.dart';
import '../services/activity_history_repository.dart';
import '../services/activity_history_tracker.dart';
import '../services/audio_level_service.dart';
import '../services/calibration.dart';
import '../services/keep_screen_on_service.dart';
import '../services/repositories.dart';
import '../services/sound_detector.dart';
import '../services/sources.dart';
import '../services/tts_service.dart';
import 'training_session_controller.dart';

class AppController extends ChangeNotifier {
  AppController({
    SettingsRepository? settingsRepository,
    StatisticsRepository? statisticsRepository,
    ActivityHistoryRepository? activityHistoryRepository,
    AudioLevelService? audio,
    TtsService? tts,
    KeepScreenOnService? keepScreenOn,
    DateTime Function()? now,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _statisticsRepository = statisticsRepository ?? StatisticsRepository(),
       _activityHistoryRepository =
           activityHistoryRepository ?? ActivityHistoryRepository(),
       _audio = audio ?? AudioLevelService(),
       tts = tts ?? AndroidTtsService(),
       _keepScreenOn = keepScreenOn ?? AndroidKeepScreenOnService(),
       _now = now ?? DateTime.now;

  final SettingsRepository _settingsRepository;
  final StatisticsRepository _statisticsRepository;
  final ActivityHistoryRepository _activityHistoryRepository;
  final AudioLevelService _audio;
  final KeepScreenOnService _keepScreenOn;
  final DateTime Function() _now;
  final TtsService tts;
  StreamSubscription<double>? _levelSubscription;
  late TrainingSessionController session;
  TrainingSettings settings = TrainingSettings.defaults;
  TrainingStatistics statistics = const TrainingStatistics();
  List<TtsVoice> voices = [];
  bool initialized = false;
  bool microphoneAvailable = true;
  bool trainingEnabled = false;
  double currentLevelDb = -80;
  bool calibrating = false;
  int calibrationSecondsLeft = 0;
  final List<double> _calibrationSamples = [];
  DateTime? _calibrationStartedAt;
  bool _microphoneCaptureSuspended = false;
  bool _lifecyclePaused = false;
  Timer? _scheduleTimer;
  Timer? _scheduleTransitionTimer;
  Timer? _activityCheckpointTimer;
  late final ActivityHistoryTracker _activityHistory;
  TrainingStatistics? _lastRecordedStatistics;

  bool get isWaitingForSchedule =>
      trainingEnabled && !settings.isTrainingAllowedAt(_now());

  Future<void> initialize() async {
    settings = await _settingsRepository.load();
    statistics = await _statisticsRepository.load();
    _lastRecordedStatistics = statistics;
    _activityHistory = ActivityHistoryTracker(
      _activityHistoryRepository,
      onChanged: notifyListeners,
    );
    final detector = ThresholdSoundDetector(
      initialThresholdDb: settings.soundThresholdDb,
    );
    session = TrainingSessionController(
      initialSettings: settings,
      initialStatistics: statistics,
      soundDetector: detector,
      ttsService: tts,
      sessionClock: SystemClock(),
      randomSource: DartRandomSource(),
      onStatisticsChanged: (value) async {
        final before = _lastRecordedStatistics ?? value;
        final now = _now();
        statistics = value;
        _lastRecordedStatistics = value;
        await _activityHistory.checkpoint(now);
        await _activityHistory.recordDelta(before, value, now);
        await _statisticsRepository.save(value);
        notifyListeners();
      },
      microphoneCapture: _AppMicrophoneCaptureCoordinator(
        onPause: _suspendAudioCaptureForSpeech,
        onResume: _resumeAudioCaptureAfterSpeech,
      ),
    );
    session.addListener(_sessionChanged);
    _levelSubscription = _audio.levels.listen((level) {
      currentLevelDb = level;
      final started = _calibrationStartedAt;
      if (calibrating &&
          started != null &&
          _now().difference(started) >= const Duration(seconds: 2)) {
        _calibrationSamples.add(level);
      }
      session.handleAudioLevel(level);
      notifyListeners();
    });
    try {
      microphoneAvailable = await _audio.start();
    } catch (_) {
      microphoneAvailable = false;
    }
    try {
      voices = await tts.getVoices();
      session.updateVoices(voices);
    } catch (_) {
      voices = [];
    }
    initialized = true;
    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_synchronizeTrainingWithSchedule()),
    );
    _scheduleNextTransition();
    notifyListeners();
  }

  void _sessionChanged() {
    statistics = session.statistics;
    notifyListeners();
  }

  Future<void> updateSettings(TrainingSettings value) async {
    settings = value;
    session.updateSettings(value);
    await _settingsRepository.save(value);
    await _synchronizeTrainingWithSchedule();
  }

  Future<bool> startTraining() async {
    trainingEnabled = true;
    final allowed = settings.isTrainingAllowedAt(_now());
    await _synchronizeTrainingWithSchedule();
    notifyListeners();
    return !allowed || session.isRunning;
  }

  Future<void> stopTraining() async {
    trainingEnabled = false;
    _scheduleTransitionTimer?.cancel();
    _scheduleTransitionTimer = null;
    await _stopActiveSession();
    notifyListeners();
  }

  Future<bool> _startActiveSession() async {
    if (session.isRunning) return true;
    if (_microphoneCaptureSuspended || _lifecyclePaused) return false;
    if (!microphoneAvailable) {
      try {
        microphoneAvailable = await _audio.start();
      } catch (_) {
        microphoneAvailable = false;
      }
    }
    if (!microphoneAvailable) {
      notifyListeners();
      return false;
    }
    final now = _now();
    _activityHistory.start(now);
    session.start();
    _activityCheckpointTimer ??= Timer.periodic(const Duration(seconds: 45), (
      _,
    ) {
      if (session.isRunning) {
        unawaited(_activityHistory.checkpoint(_now()));
      }
    });
    await _syncPowerMode();
    return true;
  }

  Future<void> _stopActiveSession() async {
    try {
      if (session.isRunning) {
        await _activityHistory.stop(_now());
      }
      await session.stop();
    } finally {
      _activityCheckpointTimer?.cancel();
      _activityCheckpointTimer = null;
      await _syncPowerMode();
    }
  }

  Future<void> pauseForBackground() async {
    if (settings.allowScreenToSleep) return;
    _lifecyclePaused = true;
    await _stopActiveSession();
    await _audio.stop();
  }

  Future<void> resumeForeground() async {
    if (_microphoneCaptureSuspended) return;
    _lifecyclePaused = false;
    await _startAudioCapture();
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> suspendMicrophoneCapture() async {
    _microphoneCaptureSuspended = true;
    await _stopActiveSession();
    await _audio.stop();
  }

  Future<void> resumeMicrophoneCapture() async {
    _microphoneCaptureSuspended = false;
    await _startAudioCapture();
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> _startAudioCapture() async {
    try {
      microphoneAvailable = await _audio.start();
    } catch (_) {
      microphoneAvailable = false;
    }
    notifyListeners();
  }

  Future<void> _suspendAudioCaptureForSpeech() => _audio.stop();

  Future<void> _resumeAudioCaptureAfterSpeech() async {
    if (_microphoneCaptureSuspended || !session.isRunning) return;
    await _startAudioCapture();
  }

  Future<void> _synchronizeTrainingWithSchedule() async {
    final shouldRun =
        trainingEnabled &&
        !_microphoneCaptureSuspended &&
        !_lifecyclePaused &&
        settings.isTrainingAllowedAt(_now());
    if (shouldRun) {
      await _startActiveSession();
    } else if (session.isRunning) {
      await _stopActiveSession();
    } else {
      await _syncPowerMode();
    }
    _scheduleNextTransition();
    notifyListeners();
  }

  void _scheduleNextTransition() {
    _scheduleTransitionTimer?.cancel();
    _scheduleTransitionTimer = null;
    if (!trainingEnabled || !settings.dailyScheduleEnabled) return;

    final now = _now();
    final transition = settings.dailySchedule.nextTransitionAfter(now);
    if (transition == null) return;
    final delay = transition.difference(now);
    _scheduleTransitionTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_synchronizeTrainingWithSchedule()),
    );
  }

  Future<void> _syncPowerMode() async {
    final running = session.isRunning;
    await _keepScreenOn.setEnabled(running && !settings.allowScreenToSleep);
    await _keepScreenOn.setBackgroundTrainingEnabled(
      running && settings.allowScreenToSleep,
    );
  }

  Future<void> resetSettings() async {
    await stopTraining();
    await _settingsRepository.reset();
    await updateSettings(TrainingSettings.defaults);
  }

  Future<void> resetStatistics() async {
    final now = _now();
    await _activityHistory.stop(now);
    statistics = const TrainingStatistics();
    session.updateStatistics(statistics);
    await _statisticsRepository.reset();
    await _activityHistoryRepository.reset();
    _lastRecordedStatistics = statistics;
    if (session.isRunning) _activityHistory.start(now);
    notifyListeners();
  }

  Future<void> calibrateMicrophone() async {
    if (calibrating) return;
    await _stopActiveSession();
    calibrating = true;
    _calibrationSamples.clear();
    _calibrationStartedAt = _now();
    for (var remaining = 10; remaining > 0; remaining--) {
      calibrationSecondsLeft = remaining;
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final threshold = MicrophoneCalibration.threshold(
      samples: _calibrationSamples,
      minimum: -80,
      maximum: 0,
    );
    calibrating = false;
    calibrationSecondsLeft = 0;
    await updateSettings(settings.copyWith(soundThresholdDb: threshold));
  }

  void markGoodAttempt() => session.markGoodAttempt();

  Future<DailyActivity?> loadActivityDay(DateTime date) =>
      _activityHistoryRepository.loadDay(date);

  Future<List<DailyActivity>> loadActivityMonth(int year, int month) =>
      _activityHistoryRepository.loadMonth(year, month);

  Future<void> previewVoice(TtsVoice voice) async {
    await _stopActiveSession();
    await tts.speak(_previewPhrase, settings, voice);
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> previewSpeechSettings() async {
    await _stopActiveSession();
    await tts.speak(_previewPhrase, settings, null);
    await _synchronizeTrainingWithSchedule();
  }

  String get _previewPhrase => switch (
    AppLanguage.resolve(PlatformDispatcher.instance.locale.languageCode)
  ) {
    AppLanguage.english => 'Good bird!',
    AppLanguage.russian => 'Привет, моя птичка',
    AppLanguage.spanish => '¡Buen pajarito!',
  };

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    session.dispose();
    _scheduleTimer?.cancel();
    _scheduleTransitionTimer?.cancel();
    _activityCheckpointTimer?.cancel();
    _levelSubscription?.cancel();
    unawaited(_keepScreenOn.setEnabled(false));
    unawaited(_keepScreenOn.setBackgroundTrainingEnabled(false));
    unawaited(_audio.dispose());
    super.dispose();
  }
}

class _AppMicrophoneCaptureCoordinator implements MicrophoneCaptureCoordinator {
  const _AppMicrophoneCaptureCoordinator({
    required this.onPause,
    required this.onResume,
  });

  final Future<void> Function() onPause;
  final Future<void> Function() onResume;

  @override
  Future<void> pause() => onPause();

  @override
  Future<void> resume() => onResume();
}
