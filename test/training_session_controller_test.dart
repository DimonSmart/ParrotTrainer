import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/controllers/training_session_controller.dart';
import 'package:parrot_trainer/models/training_phrase.dart';
import 'package:parrot_trainer/models/training_settings.dart';
import 'package:parrot_trainer/models/training_statistics.dart';
import 'package:parrot_trainer/services/recorded_phrase_player.dart';
import 'package:parrot_trainer/services/sound_detector.dart';
import 'package:parrot_trainer/services/sources.dart';
import 'package:parrot_trainer/services/tts_service.dart';

void main() {
  group('TrainingSessionController', () {
    test('minimum protection: early sound is answered only at Tmin', () async {
      final fixture = Fixture();
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 2));
      fixture.controller.handleSoundChanged(true);
      fixture.clock.advance(const Duration(milliseconds: 200));
      fixture.controller.handleSoundChanged(false);
      fixture.clock.advance(const Duration(seconds: 2, milliseconds: 700));
      fixture.controller.tick();
      expect(fixture.tts.calls, 0);
      fixture.clock.advance(const Duration(milliseconds: 100));
      fixture.controller.tick();
      await flushAsync();
      expect(fixture.tts.calls, 1);
      expect(fixture.controller.statistics.responsesToSound, 1);
    });

    test('normal response waits for configured silence after chirp', () async {
      final fixture = Fixture();
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 6));
      fixture.controller.handleSoundChanged(true);
      fixture.clock.advance(const Duration(seconds: 1));
      fixture.controller.handleSoundChanged(false);
      fixture.clock.advance(const Duration(milliseconds: 1900));
      fixture.controller.tick();
      expect(fixture.tts.calls, 0);
      fixture.clock.advance(const Duration(milliseconds: 100));
      fixture.controller.tick();
      await flushAsync();
      expect(fixture.controller.statistics.responsesToSound, 1);
    });

    test('timeout speaks at Tmax when there was no sound', () async {
      final fixture = Fixture();
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 30));
      fixture.controller.tick();
      await flushAsync();
      expect(fixture.tts.calls, 1);
      expect(fixture.controller.statistics.timeoutPhrases, 1);
    });

    test('recorded audio has priority and TTS remains the fallback', () async {
      final recordedPlayer = FakeRecordedPlayer(available: true);
      final recorded = Fixture(
        recordedPlayer: recordedPlayer,
        phrases: const [
          TrainingPhrase(
            id: 'recorded',
            text: 'Записанная',
            recordedAudioPath: '/phrase.m4a',
          ),
        ],
      );
      recorded.controller.start();
      recorded.clock.advance(const Duration(seconds: 30));
      recorded.controller.tick();
      await flushAsync();
      expect(recordedPlayer.paths, ['/phrase.m4a']);
      expect(recorded.tts.calls, 0);

      final missingPlayer = FakeRecordedPlayer(available: false);
      final fallback = Fixture(
        recordedPlayer: missingPlayer,
        phrases: const [
          TrainingPhrase(
            id: 'missing',
            text: 'Через TTS',
            recordedAudioPath: '/missing.m4a',
          ),
        ],
      );
      fallback.controller.start();
      fallback.clock.advance(const Duration(seconds: 30));
      fallback.controller.tick();
      await flushAsync();
      expect(fallback.tts.calls, 1);
    });

    test('countdown switches to the short silence delay after a chirp', () {
      final fixture = Fixture();
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 6));
      fixture.controller.handleSoundChanged(true);
      fixture.clock.advance(const Duration(seconds: 1));
      fixture.controller.handleSoundChanged(false);

      expect(
        fixture.controller.timeUntilNextSpeech,
        const Duration(seconds: 2),
      );
      expect(fixture.controller.nextSpeechProgress, closeTo(7 / 9, .001));
    });

    test('continuous sound through Tmax is never interrupted', () async {
      final fixture = Fixture();
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 6));
      fixture.controller.handleSoundChanged(true);
      fixture.clock.advance(const Duration(seconds: 30));
      fixture.controller.tick();
      expect(fixture.tts.calls, 0);
      fixture.controller.handleSoundChanged(false);
      fixture.clock.advance(const Duration(seconds: 2));
      fixture.controller.tick();
      await flushAsync();
      expect(fixture.controller.statistics.responsesToSound, 1);
      expect(fixture.controller.statistics.timeoutPhrases, 0);
    });

    test(
      'microphone events during own TTS do not become bird responses',
      () async {
        final tts = FakeTts(block: true);
        final fixture = Fixture(tts: tts);
        fixture.controller.start();
        fixture.clock.advance(const Duration(seconds: 30));
        fixture.controller.tick();
        expect(fixture.controller.state, TrainingState.speaking);
        fixture.controller.handleSoundChanged(true);
        fixture.controller.handleSoundChanged(false);
        expect(fixture.controller.statistics.soundEvents, 0);
        await flushAsync();
        await flushAsync();
        tts.completeSpeech();
        await flushAsync();
        await flushAsync();
        fixture.clock.advance(TrainingSessionController.postSpeechGuard);
        fixture.controller.tick();
        expect(fixture.controller.statistics.timeoutPhrases, 1);
        expect(fixture.controller.statistics.responsesToSound, 0);
      },
    );

    test(
      'multiple chirps separated by short pauses form one response',
      () async {
        final fixture = Fixture();
        fixture.controller.start();
        fixture.clock.advance(const Duration(seconds: 6));
        fixture.controller.handleSoundChanged(true);
        fixture.clock.advance(const Duration(milliseconds: 500));
        fixture.controller.handleSoundChanged(false);
        fixture.clock.advance(const Duration(seconds: 1));
        fixture.controller.handleSoundChanged(true);
        fixture.clock.advance(const Duration(milliseconds: 500));
        fixture.controller.handleSoundChanged(false);
        fixture.clock.advance(const Duration(milliseconds: 1900));
        fixture.controller.tick();
        expect(fixture.tts.calls, 0);
        fixture.clock.advance(const Duration(milliseconds: 100));
        fixture.controller.tick();
        await flushAsync();
        expect(fixture.tts.calls, 1);
        expect(fixture.controller.statistics.soundEvents, 2);
      },
    );

    test('cycle intervals restart after actual TTS completion', () async {
      final tts = FakeTts(block: true);
      final fixture = Fixture(tts: tts);
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 30));
      fixture.controller.tick();
      fixture.clock.advance(const Duration(seconds: 4));
      await flushAsync();
      await flushAsync();
      tts.completeSpeech();
      await flushAsync();
      await flushAsync();
      expect(fixture.controller.state, TrainingState.postSpeechGuard);
      fixture.clock.advance(TrainingSessionController.postSpeechGuard);
      fixture.controller.tick();
      expect(fixture.controller.cycleStartedAt, fixture.clock.now());
      fixture.clock.advance(const Duration(seconds: 29));
      fixture.controller.tick();
      expect(tts.calls, 1);
      fixture.clock.advance(const Duration(seconds: 1));
      fixture.controller.tick();
      await flushAsync();
      expect(tts.calls, 2);
    });

    test('statistics classify response and timeout independently', () async {
      final fixture = Fixture();
      fixture.controller.start();
      fixture.clock.advance(const Duration(seconds: 5));
      fixture.controller.handleSoundChanged(true);
      fixture.clock.advance(const Duration(seconds: 1));
      fixture.controller.handleSoundChanged(false);
      fixture.clock.advance(const Duration(seconds: 2));
      fixture.controller.tick();
      await flushAsync();
      fixture.clock.advance(TrainingSessionController.postSpeechGuard);
      fixture.controller.tick();
      fixture.clock.advance(const Duration(seconds: 30));
      fixture.controller.tick();
      await flushAsync();
      final stats = fixture.controller.statistics;
      expect(stats.totalPhrasesSpoken, 2);
      expect(stats.responsesToSound, 1);
      expect(stats.timeoutPhrases, 1);
      expect(stats.responsePercent, 50);
    });

    test(
      'sound during post TTS guard is ignored and sound after it is accepted',
      () async {
        final fixture = Fixture();
        fixture.controller.start();
        fixture.clock.advance(const Duration(seconds: 30));
        fixture.controller.tick();
        await flushAsync();
        await flushAsync();
        expect(fixture.controller.state, TrainingState.postSpeechGuard);
        fixture.controller.handleSoundChanged(true);
        expect(fixture.controller.statistics.soundEvents, 0);
        fixture.clock.advance(TrainingSessionController.postSpeechGuard);
        fixture.controller.tick();
        fixture.controller.handleSoundChanged(true);
        expect(fixture.controller.statistics.soundEvents, 1);
        expect(fixture.controller.statistics.birdRepliesAfterApp, 1);
      },
    );

    test(
      'microphone capture is paused for speech and resumed after its guard',
      () async {
        final capture = FakeCaptureCoordinator();
        final fixture = Fixture(capture: capture);
        fixture.controller.start();
        fixture.clock.advance(const Duration(seconds: 30));
        fixture.controller.tick();
        await flushAsync();
        await flushAsync();

        expect(capture.pauses, 1);
        expect(capture.resumes, 0);

        fixture.clock.advance(TrainingSessionController.postSpeechGuard);
        fixture.controller.tick();
        await flushAsync();

        expect(capture.resumes, 1);
      },
    );

    test(
      'idle prompts stop after unanswered limit and bird breaks quiet period',
      () async {
        final fixture = Fixture();
        fixture.controller.start();
        for (var i = 0; i < 2; i++) {
          fixture.clock.advance(const Duration(seconds: 30));
          fixture.controller.tick();
          await flushAsync();
          await flushAsync();
          fixture.clock.advance(TrainingSessionController.postSpeechGuard);
          fixture.controller.tick();
          fixture.clock.advance(TrainingSessionController.birdReplyWindow);
          fixture.controller.tick();
        }
        expect(fixture.controller.state, TrainingState.quietPeriod);
        fixture.controller.handleSoundChanged(true);
        expect(fixture.controller.state, TrainingState.soundDetected);
      },
    );
  });

  test('dBFS normalization converts in both directions', () {
    expect(dbToNormalized(-80), 0);
    expect(dbToNormalized(0), 1);
    expect(normalizedToDb(.5), -40);
  });
}

Future<void> flushAsync() => Future<void>.delayed(Duration.zero);

class Fixture {
  Fixture({
    FakeTts? tts,
    RecordedPhrasePlayer? recordedPlayer,
    FakeCaptureCoordinator? capture,
    List<TrainingPhrase>? phrases,
  }) : tts = tts ?? FakeTts() {
    controller = TrainingSessionController(
      initialSettings: TrainingSettings.defaults.copyWith(
        phrases: phrases,
        idlePromptMinInterval: const Duration(seconds: 30),
        idlePromptMaxInterval: const Duration(seconds: 30),
      ),
      initialStatistics: const TrainingStatistics(),
      soundDetector: FakeDetector(),
      ttsService: this.tts,
      sessionClock: clock,
      randomSource: FixedRandom(),
      recordedPhrasePlayer: recordedPlayer,
      microphoneCapture: capture,
      enableAutomaticTicks: false,
    );
  }
  final FakeClock clock = FakeClock();
  final FakeTts tts;
  late final TrainingSessionController controller;
}

class FakeRecordedPlayer implements RecordedPhrasePlayer {
  FakeRecordedPlayer({required this.available});
  final bool available;
  final List<String?> paths = [];

  @override
  Future<bool> playIfAvailable(String? path) async {
    paths.add(path);
    return available;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class FakeCaptureCoordinator implements MicrophoneCaptureCoordinator {
  int pauses = 0;
  int resumes = 0;

  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> resume() async => resumes++;
}

class FakeClock implements Clock {
  DateTime value = DateTime.utc(2026);
  void advance(Duration duration) => value = value.add(duration);
  @override
  DateTime now() => value;
}

class FixedRandom implements RandomSource {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
}

class FakeDetector implements SoundDetector {
  @override
  double currentLevelDb = -80;
  @override
  bool isSoundDetected = false;
  @override
  SoundTransition? addSample(double levelDb, DateTime now) {
    currentLevelDb = levelDb;
    return null;
  }

  @override
  void reset() => isSoundDetected = false;
  @override
  void setThreshold(double thresholdDb) {}
}

class FakeTts implements TtsService {
  FakeTts({this.block = false});
  final bool block;
  int calls = 0;
  Completer<void>? _completer;
  @override
  Future<List<TtsVoice>> getVoices() async => [];
  @override
  Future<void> speak(
    String phrase,
    TrainingSettings settings,
    TtsVoice? voice,
  ) {
    calls++;
    if (!block) return Future.value();
    _completer = Completer<void>();
    return _completer!.future;
  }

  void completeSpeech() => _completer?.complete();
  @override
  Future<void> stop() async {
    if (_completer != null && !_completer!.isCompleted) _completer!.complete();
  }
}
