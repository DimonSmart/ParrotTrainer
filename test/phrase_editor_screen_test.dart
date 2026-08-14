import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/models/training_phrase.dart';
import 'package:parrot_trainer/services/phrase_recorder.dart';
import 'package:parrot_trainer/services/recorded_phrase_player.dart';
import 'package:parrot_trainer/services/speech_recognition_service.dart';
import 'package:parrot_trainer/ui/phrase_editor_screen.dart';

void main() {
  const original = TrainingPhrase(id: 'original', text: 'Привет');

  testWidgets('+ creates a text phrase without starting recording', (
    tester,
  ) async {
    final fixture = await _pumpEditor(tester, const [original]);

    await tester.tap(find.byKey(const Key('addTextPhrase')));
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(fixture.speech.startCalls, 0);
    expect(fixture.recorder.startedIds, isEmpty);
  });

  testWidgets('voice action creates a phrase and starts recording', (
    tester,
  ) async {
    final fixture = await _pumpEditor(tester, const [original]);

    await tester.tap(find.byKey(const Key('addVoicePhrase')));
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(fixture.speech.startCalls, 1);
    expect(find.text('Остановить'), findsOneWidget);
  });

  testWidgets('successful recognition fills empty text', (tester) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.result = const SpeechRecognitionResult(
      audioPath: '/recording.wav',
      text: 'Доброе утро',
    );

    await recordNewVoicePhrase(tester);

    expect(lastText(tester), 'Доброе утро');
  });

  testWidgets('empty recognition leaves text empty', (tester) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.result = const SpeechRecognitionResult(
      audioPath: '/recording.wav',
      text: '  ',
    );

    await recordNewVoicePhrase(tester);

    expect(lastText(tester), isEmpty);
  });

  testWidgets('recognition error keeps recorded audio', (tester) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.result = SpeechRecognitionResult(
      audioPath: '/recording.wav',
      error: StateError('recognizer failed'),
    );

    await recordNewVoicePhrase(tester);

    expect(fixture.recorder.deletedPaths, isEmpty);
    expect(
      find.text('Запись сохранена, но речь распознать не удалось'),
      findsOneWidget,
    );
  });

  testWidgets('rerecording never replaces non-empty text', (tester) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.result = const SpeechRecognitionResult(
      audioPath: '/new.wav',
      text: 'Другой текст',
    );

    await tester.tap(find.byKey(const Key('recordPhrase-original')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recordPhrase-original')));
    await tester.pump();

    expect(textFor(tester, 'original'), 'Привет');
  });

  testWidgets('rerecording fills existing empty text', (tester) async {
    final fixture = await _pumpEditor(tester, const [
      TrainingPhrase(id: 'empty', text: ''),
    ]);
    fixture.speech.result = const SpeechRecognitionResult(
      audioPath: '/new.wav',
      text: 'Новый текст',
    );

    await tester.tap(find.byKey(const Key('recordPhrase-empty')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recordPhrase-empty')));
    await tester.pump();

    expect(textFor(tester, 'empty'), 'Новый текст');
  });

  testWidgets('save validates a recorded phrase with empty text', (
    tester,
  ) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.result = const SpeechRecognitionResult(
      audioPath: '/recording.wav',
    );
    await recordNewVoicePhrase(tester);

    await tester.tap(find.byKey(const Key('savePhrases')));
    await tester.pump();

    expect(find.text('Введите текст записанной фразы'), findsOneWidget);
    expect(find.byType(PhraseEditorScreen), findsOneWidget);
  });

  testWidgets('speech permission denial falls back to manual recording', (
    tester,
  ) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.startError = StateError('permission denied');
    fixture.recorder.stopPath = '/manual.m4a';

    await tester.tap(find.byKey(const Key('addVoicePhrase')));
    await tester.pump();
    expect(fixture.recorder.startedIds, hasLength(1));
    expect(fixture.events, ['speech.start', 'speech.cancel', 'recorder.start']);
    await tester.tap(find.text('Остановить'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Вручную');
    await tester.pump();

    expect(lastText(tester), 'Вручную');
    expect(find.text('Не удалось начать запись'), findsNothing);
  });

  testWidgets('empty coordinated audio switches later recordings to fallback', (
    tester,
  ) async {
    final fixture = await _pumpEditor(tester, const [original]);
    fixture.speech.stopError = const EmptyAudioRecordingException();

    await recordNewVoicePhrase(tester);
    expect(find.text('Не удалось записать звук'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addVoicePhrase')));
    await tester.pump();

    expect(fixture.speech.startCalls, 1);
    expect(fixture.recorder.startedIds, hasLength(1));
  });

  testWidgets(
    'recognition error with audio keeps coordinated recording enabled',
    (tester) async {
      final fixture = await _pumpEditor(tester, const [original]);
      fixture.speech.result = SpeechRecognitionResult(
        audioPath: '/recording.wav',
        error: StateError('recognizer failed'),
      );

      await recordNewVoicePhrase(tester);
      await tester.tap(find.byKey(const Key('addVoicePhrase')));
      await tester.pump();

      expect(fixture.speech.startCalls, 2);
      expect(fixture.recorder.startedIds, isEmpty);
    },
  );

  testWidgets('background cancels an active speech-recognition recording', (
    tester,
  ) async {
    final fixture = await _pumpEditor(tester, const [original]);
    await tester.tap(find.byKey(const Key('addVoicePhrase')));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(fixture.speech.cancelCalls, 1);
    expect(find.text('Остановить'), findsNothing);
  });
}

Future<_EditorFixture> _pumpEditor(
  WidgetTester tester,
  List<TrainingPhrase> phrases,
) async {
  final fixture = _EditorFixture();
  await tester.pumpWidget(
    MaterialApp(
      home: PhraseEditorScreen(
        phrases: phrases,
        recorder: fixture.recorder,
        speechRecognition: fixture.speech,
        player: fixture.player,
      ),
    ),
  );
  return fixture;
}

Future<void> recordNewVoicePhrase(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('addVoicePhrase')));
  await tester.pump();
  await tester.tap(find.text('Остановить'));
  await tester.pump();
}

String lastText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!.text;

String textFor(WidgetTester tester, String id) => tester
    .widget<TextField>(find.byKey(Key('phraseText-$id')))
    .controller!
    .text;

class _EditorFixture {
  late final recorder = FakeRecorder(events);
  late final speech = FakeSpeechRecognition(events);
  final player = FakePlayer();
  final events = <String>[];
}

class FakeRecorder implements PhraseRecordingService {
  FakeRecorder(this.events);

  final List<String> events;
  final List<String> startedIds = [];
  final List<String?> deletedPaths = [];
  String? stopPath = '/fallback.m4a';

  @override
  Future<void> start(String phraseId) async {
    events.add('recorder.start');
    startedIds.add(phraseId);
  }

  @override
  Future<String?> stop() async => stopPath;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String? path) async => deletedPaths.add(path);
  @override
  Future<void> dispose() async {}
}

class FakeSpeechRecognition implements SpeechRecognitionService {
  FakeSpeechRecognition(this.events);

  final List<String> events;
  int startCalls = 0;
  int cancelCalls = 0;
  Object? startError;
  Object? stopError;
  SpeechRecognitionResult result = const SpeechRecognitionResult(
    audioPath: '/recording.wav',
  );

  @override
  Future<bool> isAvailable() async => startError == null;
  @override
  Future<void> start(String phraseId) async {
    events.add('speech.start');
    startCalls++;
    if (startError != null) throw startError!;
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    if (stopError != null) throw stopError!;
    return result;
  }

  @override
  Future<void> cancel() async {
    events.add('speech.cancel');
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {}
}

class FakePlayer implements RecordedPhrasePlayer {
  @override
  Future<bool> playIfAvailable(String? path) async => path != null;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
