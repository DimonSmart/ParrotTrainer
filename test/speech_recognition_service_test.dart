import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/services/speech_recognition_service.dart';
import 'package:stt_record/stt_record.dart';

void main() {
  test(
    'a failed start releases the native session before a new start',
    () async {
      final session = _FakeSession()..startError = StateError('busy');
      final service = SystemSpeechRecognitionService(session: session);

      await expectLater(service.start('first'), throwsStateError);
      expect(session.events, ['start', 'cancel']);

      session.startError = null;
      await service.start('second');
      expect(session.events, ['start', 'cancel', 'start']);

      await service.cancel();
      await service.cancel();
      expect(session.events, ['start', 'cancel', 'start', 'cancel', 'cancel']);
    },
  );

  test('a failed stop releases the partially active native session', () async {
    final session = _FakeSession()..stopError = StateError('stop failed');
    final service = SystemSpeechRecognitionService(session: session);
    await service.start('phrase');

    await expectLater(service.stop(), throwsStateError);

    expect(session.events, ['start', 'stop', 'cancel']);
  });
}

class _FakeSession implements CoordinatedSpeechSession {
  final events = <String>[];
  final _transcripts = StreamController<SttRecordTranscript>.broadcast();
  Object? startError;
  Object? stopError;

  @override
  Stream<SttRecordTranscript> get transcripts => _transcripts.stream;

  @override
  Future<void> cancel() async => events.add('cancel');

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start({required String localeId}) async {
    events.add('start');
    if (startError != null) throw startError!;
  }

  @override
  Future<String> stop() async {
    events.add('stop');
    if (stopError != null) throw stopError!;
    throw UnimplementedError();
  }
}
