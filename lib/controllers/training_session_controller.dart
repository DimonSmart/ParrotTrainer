import 'dart:async';
import 'package:flutter/foundation.dart';
import '../l10n/app_language.dart';
import '../models/training_phrase.dart';
import '../models/training_settings.dart';
import '../models/training_statistics.dart';
import '../services/recorded_phrase_player.dart';
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
  postSpeechGuard,
  quietPeriod,
}

enum SpeechReason { responseToSound, idle }

abstract interface class MicrophoneCaptureCoordinator {
  Future<void> pause();
  Future<void> resume();
}

class TrainingSessionController extends ChangeNotifier {
  TrainingSessionController({
    required TrainingSettings initialSettings,
    required TrainingStatistics initialStatistics,
    required SoundDetector soundDetector,
    required TtsService ttsService,
    required Clock sessionClock,
    required RandomSource randomSource,
    RecordedPhrasePlayer? recordedPhrasePlayer,
    this.microphoneCapture,
    this.onStatisticsChanged,
    bool enableAutomaticTicks = true,
  }) : _settings = initialSettings,
       _statistics = initialStatistics,
       _detector = soundDetector,
       _tts = ttsService,
       _clock = sessionClock,
       _random = randomSource,
       _recordedPlayer = recordedPhrasePlayer ?? LocalRecordedPhrasePlayer(),
       _autoTick = enableAutomaticTicks;
  static const postSpeechGuard = Duration(seconds: 2),
      birdReplyWindow = Duration(seconds: 10),
      quietPeriodDuration = Duration(minutes: 5),
      maxDeferredReplyDelay = Duration(seconds: 2);
  TrainingSettings _settings;
  TrainingStatistics _statistics;
  final SoundDetector _detector;
  final TtsService _tts;
  final RecordedPhrasePlayer _recordedPlayer;
  final Clock _clock;
  final RandomSource _random;
  final bool _autoTick;
  final MicrophoneCaptureCoordinator? microphoneCapture;
  final Future<void> Function(TrainingStatistics)? onStatisticsChanged;
  Timer? _timer;
  DateTime? _cycleStartedAt,
      _lastSoundAt,
      _idleDeadline,
      _guardEndsAt,
      _replyWindowEndsAt,
      _quietEndsAt;
  bool _hasSound = false,
      _isSoundActive = false,
      _replyRecorded = false,
      _running = false,
      _idleReplyPending = false;
  int _operation = 0, _consecutiveUnansweredIdlePrompts = 0;
  String? _previousVoiceId;
  TrainingPhrase? _lastPhrase;
  List<TtsVoice> _voices = [];
  TrainingState state = TrainingState.stopped;
  bool get isRunning => _running;
  bool get isSoundActive => _isSoundActive;
  double get currentLevelDb => _detector.currentLevelDb;
  TrainingStatistics get statistics => _statistics;
  TrainingPhrase? get lastPhrase => _lastPhrase;
  DateTime? get cycleStartedAt => _cycleStartedAt;
  int get consecutiveUnansweredIdlePrompts => _consecutiveUnansweredIdlePrompts;
  DateTime? get nextSpeechAt {
    if (!_running ||
        state == TrainingState.speaking ||
        state == TrainingState.postSpeechGuard ||
        state == TrainingState.quietPeriod) {
      return null;
    }
    if (_hasSound && !_isSoundActive && _lastSoundAt != null) {
      final natural = _lastSoundAt!.add(_settings.silenceAfterSound);
      final min = _cycleStartedAt!.add(_settings.minimumInterval);
      final allowed = natural.isAfter(min) ? natural : min;
      return allowed.difference(natural) <= maxDeferredReplyDelay
          ? allowed
          : null;
    }
    return _idleDeadline;
  }

  Duration? get timeUntilNextSpeech => nextSpeechAt == null
      ? null
      : (nextSpeechAt!.difference(_clock.now()).isNegative
            ? Duration.zero
            : nextSpeechAt!.difference(_clock.now()));
  double? get nextSpeechProgress {
    final target = nextSpeechAt;
    if (target == null || _cycleStartedAt == null) return null;
    final total = target.difference(_cycleStartedAt!).inMilliseconds;
    return total <= 0
        ? 1
        : (_clock.now().difference(_cycleStartedAt!).inMilliseconds / total)
              .clamp(0, 1);
  }

  String _localized(String english, String russian, String spanish) =>
      switch (
        AppLanguage.resolve(PlatformDispatcher.instance.locale.languageCode)
      ) {
        AppLanguage.english => english,
        AppLanguage.russian => russian,
        AppLanguage.spanish => spanish,
      };

  String get stateLabel => switch (state) {
    TrainingState.stopped => _localized(
      'Training is off',
      'Программа выключена',
      'Entrenamiento desactivado',
    ),
    TrainingState.minimumInterval => _localized(
      'Safety interval',
      'Защитный интервал',
      'Intervalo de seguridad',
    ),
    TrainingState.listening =>
      _localized('Listening', 'Слушаю', 'Escuchando'),
    TrainingState.soundDetected =>
      _localized('Parrot detected', 'Слышу попугая', 'Loro detectado'),
    TrainingState.waitingForSilence => _localized(
      'Waiting for silence',
      'Жду тишины',
      'Esperando silencio',
    ),
    TrainingState.speaking => _localized('Speaking', 'Говорю', 'Hablando'),
    TrainingState.postSpeechGuard =>
      _localized('Listening…', 'Слушаю…', 'Escuchando…'),
    TrainingState.quietPeriod =>
      _localized('Quiet pause', 'Тихая пауза', 'Pausa silenciosa'),
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
    await _recordedPlayer.stop();
    _detector.reset();
    _isSoundActive = false;
    state = TrainingState.stopped;
    notifyListeners();
  }

  void handleAudioLevel(double levelDb) {
    if (state == TrainingState.speaking ||
        state == TrainingState.postSpeechGuard) {
      return;
    }
    final transition = _detector.addSample(levelDb, _clock.now());
    if (transition == SoundTransition.started) handleSoundChanged(true);
    if (transition == SoundTransition.ended) handleSoundChanged(false);
    notifyListeners();
  }

  @visibleForTesting
  void handleSoundChanged(bool active) {
    if (!_running ||
        state == TrainingState.speaking ||
        state == TrainingState.postSpeechGuard ||
        active == _isSoundActive) {
      return;
    }
    final now = _clock.now();
    _isSoundActive = active;
    if (active) {
      _hasSound = true;
      _lastSoundAt = now;
      if (_replyWindowEndsAt != null &&
          now.isBefore(_replyWindowEndsAt!) &&
          !_replyRecorded) {
        _replyRecorded = true;
        _idleReplyPending = false;
        _consecutiveUnansweredIdlePrompts = 0;
        _statistics = _statistics.copyWith(
          birdRepliesAfterApp: _statistics.birdRepliesAfterApp + 1,
        );
      }
      if (state == TrainingState.quietPeriod) {
        _quietEndsAt = null;
        _resetCycle(now, preserveReplyWindow: true);
        _hasSound = true;
        _isSoundActive = true;
      }
      _statistics = _statistics.copyWith(
        soundEvents: _statistics.soundEvents + 1,
      );
      _saveStats();
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
    if (!_running || state == TrainingState.speaking) return;
    final now = _clock.now();
    if (state == TrainingState.postSpeechGuard) {
      if (_guardEndsAt != null && !now.isBefore(_guardEndsAt!)) {
        _replyWindowEndsAt = now.add(birdReplyWindow);
        _resetCycle(now, preserveReplyWindow: true);
        unawaited(microphoneCapture?.resume());
      }
      return;
    }
    if (state == TrainingState.quietPeriod) {
      if (_quietEndsAt != null && !now.isBefore(_quietEndsAt!)) {
        _resetCycle(now);
      }
      return;
    }
    if (_idleReplyPending &&
        _replyWindowEndsAt != null &&
        !now.isBefore(_replyWindowEndsAt!)) {
      _idleReplyPending = false;
      _consecutiveUnansweredIdlePrompts++;
      if (_consecutiveUnansweredIdlePrompts >=
          _settings.maxConsecutiveIdlePrompts) {
        _quietEndsAt = now.add(quietPeriodDuration);
        state = TrainingState.quietPeriod;
        notifyListeners();
        return;
      }
    }
    if (_isSoundActive) {
      state = TrainingState.soundDetected;
      return;
    }
    final due = nextSpeechAt;
    if (_hasSound && _lastSoundAt != null) {
      final natural = _lastSoundAt!.add(_settings.silenceAfterSound);
      if (due == null && !now.isBefore(natural)) {
        _hasSound = false;
        _resetCycle(now, preserveReplyWindow: true);
        return;
      }
      if (due != null && !now.isBefore(due)) {
        unawaited(_speak(SpeechReason.responseToSound));
      } else {
        state = TrainingState.waitingForSilence;
        notifyListeners();
      }
      return;
    }
    if (due != null && !now.isBefore(due)) {
      unawaited(_speak(SpeechReason.idle));
    } else {
      state = now.isBefore(_cycleStartedAt!.add(_settings.minimumInterval))
          ? TrainingState.minimumInterval
          : TrainingState.listening;
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
    final phrase = _pickPhrase(reason);
    _lastPhrase = phrase;
    final enabled = _voices
        .where((v) => _settings.selectedVoiceIds.contains(v.id))
        .toList();
    final primary = enabled
        .where((v) => v.id == _settings.primaryVoiceId)
        .toList();
    final voice = _settings.primaryVoiceId == null
        ? (enabled.isEmpty
              ? null
              : _pickVoiceAvoiding(enabled, _previousVoiceId))
        : (primary.isEmpty ? null : primary.first);
    _previousVoiceId = voice?.id;
    try {
      await microphoneCapture?.pause();
      final played = await _recordedPlayer.playIfAvailable(
        phrase.recordedAudioPath,
      );
      if (!played) await _tts.speak(phrase.text, _settings, voice);
      if (!_running || operation != _operation) return;
      _statistics = _statistics.copyWith(
        totalPhrasesSpoken: _statistics.totalPhrasesSpoken + 1,
        responsesToSound:
            _statistics.responsesToSound +
            (reason == SpeechReason.responseToSound ? 1 : 0),
        timeoutPhrases:
            _statistics.timeoutPhrases + (reason == SpeechReason.idle ? 1 : 0),
        birdReplyOpportunities: _statistics.birdReplyOpportunities + 1,
      );
      await _saveStats();
      _replyRecorded = false;
      _idleReplyPending = reason == SpeechReason.idle;
      _guardEndsAt = _clock.now().add(postSpeechGuard);
      state = TrainingState.postSpeechGuard;
      notifyListeners();
    } catch (_) {
      if (_running && operation == _operation) _resetCycle(_clock.now());
      notifyListeners();
    }
  }

  TrainingPhrase _pickPhrase(SpeechReason reason) {
    final focusId = _settings.focusPhraseId;
    if (reason == SpeechReason.responseToSound && focusId != null) {
      for (final phrase in _settings.phrases) {
        if (phrase.id == focusId) return phrase;
      }
    }
    return _pickWeighted(_settings.phrases);
  }

  TrainingPhrase _pickWeighted(List<TrainingPhrase> phrases) {
    var remaining = 0.0;
    for (var i = 0; i < phrases.length; i++) {
      remaining += 1 / (1 << i);
    }
    var point = _random.nextDouble() * remaining;
    for (var i = 0; i < phrases.length; i++) {
      point -= 1 / (1 << i);
      if (point <= 0) return phrases[i];
    }
    return phrases.last;
  }

  TtsVoice _pickVoiceAvoiding(List<TtsVoice> values, String? previous) {
    final choices = values.length > 1
        ? values.where((v) => v.id != previous).toList()
        : values;
    return choices[_random.nextInt(choices.length)];
  }

  void markGoodAttempt() {
    final phrase = _lastPhrase;
    if (phrase == null) return;
    final values = Map<String, int>.from(
      _statistics.successfulAttemptsByPhrase,
    );
    values[phrase.id] = (values[phrase.id] ?? 0) + 1;
    _statistics = _statistics.copyWith(successfulAttemptsByPhrase: values);
    _saveStats();
    notifyListeners();
  }

  void _resetCycle(DateTime now, {bool preserveReplyWindow = false}) {
    _cycleStartedAt = now;
    _lastSoundAt = null;
    _hasSound = false;
    _isSoundActive = false;
    _detector.reset();
    _idleDeadline = now.add(
      _settings.idlePromptMinInterval +
          Duration(
            milliseconds:
                ((_settings.idlePromptMaxInterval -
                                _settings.idlePromptMinInterval)
                            .inMilliseconds *
                        _random.nextDouble())
                    .round(),
          ),
    );
    if (!preserveReplyWindow) _replyWindowEndsAt = null;
    state = TrainingState.minimumInterval;
  }

  Future<void> _saveStats() async => onStatisticsChanged?.call(_statistics);
  Future<void> disposeResources() => _recordedPlayer.dispose();
  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recordedPlayer.dispose());
    super.dispose();
  }
}
