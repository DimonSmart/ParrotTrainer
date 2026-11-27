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
  bool _audioCaptureActive = false;
  bool _speechCaptureSuspended = false;
  bool _previewing = false;
  bool _calibrationInterrupted = false;
  bool _screenKeptOn = false;
  bool _backgroundEnabled = false;
  bool _disposed = false;
  Future<void> _scheduleOperation = Future.value();

  bool get _canRunInBackground =>
      settings.allowScreenToSleep || settings.dailyScheduleEnabled;

  bool get _captureAllowed =>
      !_disposed &&
      !_microphoneCaptureSuspended &&
      !_speechCaptureSuspended &&
      !_previewing &&
      (!_lifecyclePaused || (trainingEnabled && _canRunInBackground)) &&
      settings.isTrainingAllowedAt(_now());

  bool get canCalibrateMicrophone => !calibrating && _captureAllowed;

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
      if (!_audioCaptureActive || !_captureAllowed) return;
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
    if (_captureAllowed) {
      await _startAudioCapture();
    } else {
      try {
        microphoneAvailable = await _audio.checkPermission();
      } catch (_) {
        microphoneAvailable = false;
      }
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
    if (!settings.isTrainingAllowedAt(_now()) && session.isRunning) {
      await _synchronizeTrainingWithSchedule();
    }
    session.updateSettings(settings);
    await _settingsRepository.save(value);
    await _synchronizeTrainingWithSchedule();
  }

  Future<bool> startTraining() async {
    trainingEnabled = true;
    final allowed = settings.isTrainingAllowedAt(_now());
    if (!microphoneAvailable) {
      try {
        microphoneAvailable = await _audio.checkPermission();
      } catch (_) {
        microphoneAvailable = false;
      }
    }
    await _synchronizeTrainingWithSchedule();
    notifyListeners();
    return (!allowed && microphoneAvailable) || session.isRunning;
  }

  Future<void> stopTraining() async {
    trainingEnabled = false;
    await _synchronizeTrainingWithSchedule();
    notifyListeners();
  }

  Future<bool> _startActiveSession() async {
    if (session.isRunning) return true;
    if (!_captureAllowed || !_audioCaptureActive) return false;
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
    return true;
  }

  Future<void> _stopActiveSession() async {
    try {
      final wasRunning = session.isRunning;
      await session.stop();
      if (wasRunning) await _activityHistory.stop(_now());
    } finally {
      _activityCheckpointTimer?.cancel();
      _activityCheckpointTimer = null;
      _speechCaptureSuspended = false;
    }
  }

  Future<void> pauseForBackground() async {
    _lifecyclePaused = true;
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> resumeForeground() async {
    _lifecyclePaused = false;
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> retryMicrophone() async {
    try {
      microphoneAvailable = await _audio.checkPermission();
    } catch (_) {
      microphoneAvailable = false;
    }
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> suspendMicrophoneCapture() async {
    _microphoneCaptureSuspended = true;
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> resumeMicrophoneCapture() async {
    _microphoneCaptureSuspended = false;
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> _startAudioCapture() async {
    if (_audioCaptureActive || !_captureAllowed || !microphoneAvailable) return;
    try {
      microphoneAvailable = await _audio.start();
      _audioCaptureActive = microphoneAvailable;
    } catch (_) {
      microphoneAvailable = false;
      _audioCaptureActive = false;
    }
    if (!_captureAllowed) await _stopAudioCapture();
  }

  Future<void> _stopAudioCapture() async {
    _audioCaptureActive = false;
    currentLevelDb = -80;
    await _audio.stop();
  }

  Future<void> _suspendAudioCaptureForSpeech() async {
    _speechCaptureSuspended = true;
    await _stopAudioCapture();
  }

  Future<void> _resumeAudioCaptureAfterSpeech() async {
    if (!session.isRunning) return;
    _speechCaptureSuspended = false;
    await _synchronizeTrainingWithSchedule();
  }

  Future<void> _synchronizeTrainingWithSchedule() {
    final result = _scheduleOperation.then((_) async {
      if (_disposed) return;
      await _applySchedule();
    });
    _scheduleOperation = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _applySchedule() async {
    final shouldRun =
        trainingEnabled &&
        !_microphoneCaptureSuspended &&
        !_previewing &&
        !calibrating &&
        (!_lifecyclePaused || _canRunInBackground) &&
        settings.isTrainingAllowedAt(_now());

    if (!shouldRun && session.isRunning) {
      if (!_captureAllowed) {
        await Future.wait([_stopActiveSession(), _stopAudioCapture()]);
      } else {
        await _stopActiveSession();
      }
    }
    if (_disposed) return;
    if (!_captureAllowed) {
      if (calibrating) _calibrationInterrupted = true;
      await _stopAudioCapture();
    } else {
      await _startAudioCapture();
    }
    if (shouldRun && !session.isRunning && _captureAllowed && trainingEnabled) {
      await _startActiveSession();
    }
    if (_disposed) return;
    await _syncPowerMode();
    if (_disposed) return;
    _scheduleNextTransition();
    notifyListeners();
  }

  void _scheduleNextTransition() {
    _scheduleTransitionTimer?.cancel();
    _scheduleTransitionTimer = null;
    if (!settings.dailyScheduleEnabled ||
        (_lifecyclePaused && !trainingEnabled)) {
      return;
    }

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
    final keepScreenOn = running && !settings.allowScreenToSleep;
    final backgroundEnabled =
        trainingEnabled &&
        microphoneAvailable &&
        !_microphoneCaptureSuspended &&
        (!_lifecyclePaused || _canRunInBackground) &&
        ((settings.dailyScheduleEnabled &&
                (!settings.dailySchedule.isUniform ||
                    settings.isTrainingAllowedAt(_now()))) ||
            (running && settings.allowScreenToSleep));

    if (_backgroundEnabled != backgroundEnabled) {
      await _keepScreenOn.setBackgroundTrainingEnabled(backgroundEnabled);
      _backgroundEnabled = backgroundEnabled;
    }
    if (_screenKeptOn != keepScreenOn) {
      await _keepScreenOn.setEnabled(keepScreenOn);
      _screenKeptOn = keepScreenOn;
    }
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
    if (!canCalibrateMicrophone) return;
    calibrating = true;
    _calibrationInterrupted = false;
    await _synchronizeTrainingWithSchedule();
    if (!_audioCaptureActive) {
      calibrating = false;
      await _synchronizeTrainingWithSchedule();
      return;
    }
    _calibrationSamples.clear();
    _calibrationStartedAt = _now();
    for (var remaining = 10; remaining > 0; remaining--) {
      calibrationSecondsLeft = remaining;
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed) return;
      if (_calibrationInterrupted || !_captureAllowed) break;
    }
    final threshold = MicrophoneCalibration.threshold(
      samples: _calibrationSamples,
      minimum: -80,
      maximum: 0,
    );
    calibrating = false;
    calibrationSecondsLeft = 0;
    if (!_calibrationInterrupted && settings.isTrainingAllowedAt(_now())) {
      await updateSettings(settings.copyWith(soundThresholdDb: threshold));
    } else {
      await _synchronizeTrainingWithSchedule();
    }
  }

  void markGoodAttempt() => session.markGoodAttempt();

  Future<DailyActivity?> loadActivityDay(DateTime date) =>
      _activityHistoryRepository.loadDay(date);

  Future<List<DailyActivity>> loadActivityMonth(int year, int month) =>
      _activityHistoryRepository.loadMonth(year, month);

  Future<void> previewVoice(TtsVoice voice) => _preview(voice);

  Future<void> previewSpeechSettings() => _preview(null);

  Future<void> _preview(TtsVoice? voice) async {
    if (_previewing) return;
    _previewing = true;
    try {
      await _synchronizeTrainingWithSchedule();
      await tts.speak(_previewPhrase, settings, voice);
    } finally {
      _previewing = false;
      await _synchronizeTrainingWithSchedule();
    }
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
    _disposed = true;
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
