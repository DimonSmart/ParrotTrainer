import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract interface class PhraseRecordingService {
  Future<void> start(String phraseId);
  Future<String?> stop();
  Future<void> cancel();
  Future<void> delete(String? path);
  Future<void> dispose();
}

class PhraseRecorder implements PhraseRecordingService {
  PhraseRecorder() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  Future<bool> get isRecording => _recorder.isRecording();

  @override
  Future<void> start(String phraseId) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was not granted');
    }
    final directory = await getApplicationDocumentsDirectory();
    final recordings = Directory(
      '${directory.path}${Platform.pathSeparator}phrase-recordings',
    );
    await recordings.create(recursive: true);
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: '${recordings.path}${Platform.pathSeparator}$phraseId.m4a',
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> delete(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
