import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/training_settings.dart';
import '../models/training_statistics.dart';
import '../services/sound_detector.dart';
import '../services/sources.dart';
import '../services/tts_service.dart';

enum TrainingState {
  stopped,
  minimumInterval,
  listening,
  soundDetected,
  waitingForSilence,
  speaking,
}

enum SpeechReason { responseToSound, timeout }

class TrainingSessionController extends ChangeNotifier {
  TrainingSessionController({
    required TrainingSettings initialSettings,
    required TrainingStatistics initialStatistics,
    required SoundDetector soundDetector,
    required TtsService ttsService,
    required Clock sessionClock,
    required RandomSource randomSource,
    this.onStatisticsChanged,
    bool enableAutomaticTicks = true,
  }) : _settings = initialSettings,
       _statistics = initialStatistics,
       _detector = soundDetector,
       _tts = ttsService,
       _clock = sessionClock,
       _random = randomSource,
       _autoTick = enableAutomaticTicks;

  TrainingSettings _settings;
  TrainingStatistics _statistics;
  final SoundDetector _detector;
  final TtsService _tts;
  final Clock _clock;
  final RandomSource _random;
  final bool _autoTick;
  final Future<void> Function(TrainingStatistics)? onStatisticsChanged;
  Timer? _timer;
  DateTime? _cycleStartedAt;
  DateTime? _lastSoundAt;
  bool _hasSoundSinceLastSpeech = false;
  bool _isSoundActive = false;
  bool _running = false;
  int _operation = 0;
  String? _previousPhrase;
  String? _previousVoiceId;
  List<TtsVoice> _voices = [];

  TrainingState state = TrainingState.stopped;
  bool get isRunning => _running;
  bool get isSoundActive => _isSoundActive;
  double get currentLevelDb => _detector.currentLevelDb;
  TrainingStatistics get statistics => _statistics;
  DateTime? get cycleStartedAt => _cycleStartedAt;

  DateTime? get nextSpeechAt {
    if (!_running ||
        state == TrainingState.speaking ||
        _cycleStartedAt == null) {
      return null;
    }
    final minimumEndsAt = _cycleStartedAt!.add(_settings.minimumInterval);
    if (!_hasSoundSinceLastSpeech) {
      return _cycleStartedAt!.add(_settings.maximumInterval);
    }
    if (_isSoundActive || _lastSoundAt == null) return null;
    final silenceEndsAt = _lastSoundAt!.add(_settings.silenceAfterSound);
    return silenceEndsAt.isAfter(minimumEndsAt) ? silenceEndsAt : minimumEndsAt;
  }

  Duration? get timeUntilNextSpeech {
    final target = nextSpeechAt;
    if (target == null) return null;
    final remaining = target.difference(_clock.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double? get nextSpeechProgress {
    final target = nextSpeechAt;
    if (target == null || _cycleStartedAt == null) return null;
    final total = target.difference(_cycleStartedAt!).inMilliseconds;
    if (total <= 0) return 1;
    final elapsed = _clock.now().difference(_cycleStartedAt!).inMilliseconds;
    return (elapsed / total).clamp(0, 1);
  }

  String get stateLabel => switch (state) {
    TrainingState.stopped => 'Программа выключена',
    TrainingState.minimumInterval => 'Защитный интервал',
    TrainingState.listening => 'Слушаю',
    TrainingState.soundDetected => 'Слышу попугая',
    TrainingState.waitingForSilence => 'Жду тишины',
    TrainingState.speaking => 'Говорю',
  };

  void updateSettings(TrainingSettings value) {
    _settings = value;
    _detector.setThreshold(value.soundThresholdDb);
    if (_running) tick();
    notifyListeners();
  }

  void updateStatistics(TrainingStatistics value) {
    _statistics = value;
    notifyListeners();
  }

  void updateVoices(List<TtsVoice> value) => _voices = value;

  void start() {
    if (_running) return;
    _running = true;
    _operation++;
    _resetCycle(_clock.now());
    if (_autoTick) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => tick());
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_running && state == TrainingState.stopped) return;
    _running = false;
    _operation++;
    _timer?.cancel();
    _timer = null;
    await _tts.stop();
    _detector.reset();
    _isSoundActive = false;
    state = TrainingState.stopped;
    notifyListeners();
  }

  void handleAudioLevel(double levelDb) {
    if (state == TrainingState.speaking) return;
    final transition = _detector.addSample(levelDb, _clock.now());
    if (transition == SoundTransition.started) handleSoundChanged(true);
    if (transition == SoundTransition.ended) handleSoundChanged(false);
    notifyListeners();
  }

  @visibleForTesting
  void handleSoundChanged(bool active) {
    if (!_running ||
        state == TrainingState.speaking ||
        active == _isSoundActive) {
      return;
    }
    final now = _clock.now();
    _isSoundActive = active;
    if (active) {
      _hasSoundSinceLastSpeech = true;
      _lastSoundAt = now;
      _statistics = _statistics.copyWith(
        soundEvents: _statistics.soundEvents + 1,
      );
      unawaited(onStatisticsChanged?.call(_statistics));
      state = TrainingState.soundDetected;
    } else {
      _lastSoundAt = now;
      state = TrainingState.waitingForSilence;
    }
    notifyListeners();
    tick();
  }

  @visibleForTesting
  void tick() {
    if (!_running ||
        state == TrainingState.speaking ||
        _cycleStartedAt == null) {
      return;
    }
    final now = _clock.now();
    if (_isSoundActive) {
      _lastSoundAt = now;
      state = TrainingState.soundDetected;
      notifyListeners();
      return;
    }

    final elapsed = now.difference(_cycleStartedAt!);
    if (elapsed < _settings.minimumInterval) {
      state = TrainingState.minimumInterval;
      notifyListeners();
      return;
    }

    if (_hasSoundSinceLastSpeech) {
      final silentFor = _lastSoundAt == null
          ? Duration.zero
          : now.difference(_lastSoundAt!);
      if (silentFor >= _settings.silenceAfterSound) {
        unawaited(_speak(SpeechReason.responseToSound));
      } else {
        state = TrainingState.waitingForSilence;
        notifyListeners();
      }
      return;
    }

    if (elapsed >= _settings.maximumInterval) {
      unawaited(_speak(SpeechReason.timeout));
    } else {
      state = TrainingState.listening;
      notifyListeners();
    }
  }

  Future<void> _speak(SpeechReason reason) async {
    if (!_running || state == TrainingState.speaking) return;
    final operation = _operation;
    state = TrainingState.speaking;
    _detector.reset();
    _isSoundActive = false;
    notifyListeners();

    final phrase = _pickAvoiding(_settings.phrases, _previousPhrase);
    _previousPhrase = phrase;
    final enabled = _voices
        .where((voice) => _settings.selectedVoiceIds.contains(voice.id))
        .toList();
    final voice = enabled.isEmpty
        ? null
        : _pickVoiceAvoiding(enabled, _previousVoiceId);
    _previousVoiceId = voice?.id;
    try {
      await _tts.speak(phrase, _settings, voice);
      if (!_running || operation != _operation) return;
      _statistics = _statistics.copyWith(
        totalPhrasesSpoken: _statistics.totalPhrasesSpoken + 1,
        responsesToSound:
            _statistics.responsesToSound +
            (reason == SpeechReason.responseToSound ? 1 : 0),
        timeoutPhrases:
            _statistics.timeoutPhrases +
            (reason == SpeechReason.timeout ? 1 : 0),
      );
      await onStatisticsChanged?.call(_statistics);
      _resetCycle(_clock.now());
      notifyListeners();
    } catch (_) {
      if (_running && operation == _operation) {
        _resetCycle(_clock.now());
        notifyListeners();
      }
    }
  }

  String _pickAvoiding(List<String> values, String? previous) {
    final choices = values.length > 1
        ? values.where((value) => value != previous).toList()
        : values;
    return choices[_random.nextInt(choices.length)];
  }

  TtsVoice _pickVoiceAvoiding(List<TtsVoice> values, String? previous) {
    final choices = values.length > 1
        ? values.where((value) => value.id != previous).toList()
        : values;
    return choices[_random.nextInt(choices.length)];
  }

  void _resetCycle(DateTime now) {
    _cycleStartedAt = now;
    _lastSoundAt = null;
    _hasSoundSinceLastSpeech = false;
    _isSoundActive = false;
    _detector.reset();
    state = TrainingState.minimumInterval;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
