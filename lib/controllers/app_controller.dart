import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/training_settings.dart';
import '../models/training_statistics.dart';
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
    AudioLevelService? audio,
    TtsService? tts,
    KeepScreenOnService? keepScreenOn,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _statisticsRepository = statisticsRepository ?? StatisticsRepository(),
       _audio = audio ?? AudioLevelService(),
       tts = tts ?? AndroidTtsService(),
       _keepScreenOn = keepScreenOn ?? AndroidKeepScreenOnService();

  final SettingsRepository _settingsRepository;
  final StatisticsRepository _statisticsRepository;
  final AudioLevelService _audio;
  final KeepScreenOnService _keepScreenOn;
  final TtsService tts;
  StreamSubscription<double>? _levelSubscription;
  late TrainingSessionController session;
  TrainingSettings settings = TrainingSettings.defaults;
  TrainingStatistics statistics = const TrainingStatistics();
  List<TtsVoice> voices = [];
  bool initialized = false;
  bool microphoneAvailable = true;
  double currentLevelDb = -80;
  bool calibrating = false;
  int calibrationSecondsLeft = 0;
  final List<double> _calibrationSamples = [];
  DateTime? _calibrationStartedAt;
  bool _microphoneCaptureSuspended = false;
  Timer? _scheduleTimer;
  Timer? _scheduleEndTimer;

  Future<void> initialize() async {
    settings = await _settingsRepository.load();
    statistics = await _statisticsRepository.load();
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
        statistics = value;
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
          DateTime.now().difference(started) >= const Duration(seconds: 2)) {
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
      (_) => unawaited(_enforceSchedule()),
    );
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
    if (session.isRunning && !settings.isWithinScheduledHours(DateTime.now())) {
      await stopTraining();
    } else {
      await _syncPowerMode();
      _scheduleStopAtEnd();
    }
    notifyListeners();
  }

  Future<bool> startTraining() async {
    if (!settings.isWithinScheduledHours(DateTime.now())) {
      notifyListeners();
      return false;
    }
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
    session.start();
    await _syncPowerMode();
    _scheduleStopAtEnd();
    return true;
  }

  Future<void> stopTraining() async {
    try {
      await session.stop();
    } finally {
      _scheduleEndTimer?.cancel();
      _scheduleEndTimer = null;
      await _syncPowerMode();
    }
  }

  Future<void> pauseForBackground() async {
    if (session.isRunning && settings.allowScreenToSleep) return;
    await stopTraining();
    await _audio.stop();
  }

  Future<void> resumeForeground() async {
    if (_microphoneCaptureSuspended) return;
    await _startAudioCapture();
  }

  Future<void> suspendMicrophoneCapture() async {
    _microphoneCaptureSuspended = true;
    await stopTraining();
    await _audio.stop();
  }

  Future<void> resumeMicrophoneCapture() async {
    _microphoneCaptureSuspended = false;
    await _startAudioCapture();
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

  Future<void> _enforceSchedule() async {
    if (session.isRunning && !settings.isWithinScheduledHours(DateTime.now())) {
      await stopTraining();
    }
  }

  void _scheduleStopAtEnd() {
    _scheduleEndTimer?.cancel();
    if (!session.isRunning ||
        !settings.dailyScheduleEnabled ||
        settings.scheduleStartMinute == settings.scheduleEndMinute) {
      return;
    }
    final now = DateTime.now();
    var end = DateTime(
      now.year,
      now.month,
      now.day,
      settings.scheduleEndMinute ~/ 60,
      settings.scheduleEndMinute % 60,
    );
    if (!end.isAfter(now)) end = end.add(const Duration(days: 1));
    _scheduleEndTimer = Timer(
      end.difference(now),
      () => unawaited(stopTraining()),
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
    statistics = const TrainingStatistics();
    session.updateStatistics(statistics);
    await _statisticsRepository.reset();
    notifyListeners();
  }

  Future<void> calibrateMicrophone() async {
    if (calibrating) return;
    await stopTraining();
    calibrating = true;
    _calibrationSamples.clear();
    _calibrationStartedAt = DateTime.now();
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

  Future<void> previewVoice(TtsVoice voice) async {
    await session.stop();
    await tts.speak('Привет, моя птичка', settings, voice);
  }

  Future<void> previewSpeechSettings() async {
    await session.stop();
    await tts.speak('Привет, моя птичка', settings, null);
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    session.dispose();
    _scheduleTimer?.cancel();
    _scheduleEndTimer?.cancel();
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
