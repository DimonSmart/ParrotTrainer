import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stt_record/stt_record.dart';

class SpeechRecognitionResult {
  const SpeechRecognitionResult({
    required this.audioPath,
    this.text,
    this.error,
  });

  final String audioPath;
  final String? text;
  final Object? error;
}

abstract interface class SpeechRecognitionService {
  Future<bool> isAvailable();
  Future<void> start(String phraseId);
  Future<SpeechRecognitionResult> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Uses one native microphone session for both recording and system speech
/// recognition, so the recognizer never competes with a second recorder.
class SystemSpeechRecognitionService implements SpeechRecognitionService {
  SystemSpeechRecognitionService({SttRecord? stt}) : _stt = stt ?? SttRecord();

  final SttRecord _stt;
  StreamSubscription<SttRecordTranscript>? _transcriptSubscription;
  String? _phraseId;
  String _latestText = '';
  Object? _recognitionError;
  static const _audioChannel = MethodChannel('parrot_trainer/audio');

  @override
  Future<bool> isAvailable() async =>
      await _isPlatformSupported() && await _stt.hasPermission();

  @override
  Future<void> start(String phraseId) async {
    if (!await _isPlatformSupported()) {
      throw UnsupportedError(
        'Coordinated speech recognition requires Android 13 or newer',
      );
    }
    if (!await _stt.requestPermission()) {
      throw StateError('Speech recognition permission was not granted');
    }
    _phraseId = phraseId;
    _latestText = '';
    _recognitionError = null;
    await _transcriptSubscription?.cancel();
    _transcriptSubscription = _stt.transcripts.listen((result) {
      final text = result.text.trim();
      if (text.isNotEmpty) _latestText = text;
    }, onError: (Object error) => _recognitionError = error);
    try {
      await _stt.start(
        localeId: PlatformDispatcher.instance.locale.toLanguageTag(),
        partialResults: true,
      );
    } catch (_) {
      await _transcriptSubscription?.cancel();
      _transcriptSubscription = null;
      _phraseId = null;
      rethrow;
    }
  }

  Future<bool> _isPlatformSupported() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _audioChannel.invokeMethod<int>('getAndroidSdkInt');
    return (sdk ?? 0) >= 33;
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    final phraseId = _phraseId;
    if (phraseId == null) throw StateError('Recognition is not running');
    String sourcePath;
    try {
      sourcePath = (await _stt.stop()).audioPath;
    } catch (_) {
      rethrow;
    } finally {
      await _transcriptSubscription?.cancel();
      _transcriptSubscription = null;
      _phraseId = null;
    }

    final directory = await getApplicationDocumentsDirectory();
    final recordings = Directory(
      '${directory.path}${Platform.pathSeparator}phrase-recordings',
    );
    await recordings.create(recursive: true);
    final wavDestination = File(
      '${recordings.path}${Platform.pathSeparator}$phraseId.wav',
    );
    final m4aDestination = File(
      '${recordings.path}${Platform.pathSeparator}$phraseId.m4a',
    );
    Object? conversionError;
    File persisted;
    if (Platform.isAndroid) {
      try {
        if (await m4aDestination.exists()) await m4aDestination.delete();
        await _audioChannel.invokeMethod<void>('convertWavToM4a', {
          'sourcePath': sourcePath,
          'destinationPath': m4aDestination.path,
        });
        persisted = m4aDestination;
      } catch (error) {
        conversionError = error;
        if (await wavDestination.exists()) await wavDestination.delete();
        persisted = await File(sourcePath).copy(wavDestination.path);
      }
    } else {
      if (await wavDestination.exists()) await wavDestination.delete();
      persisted = await File(sourcePath).copy(wavDestination.path);
    }
    return SpeechRecognitionResult(
      audioPath: persisted.path,
      text: _latestText.isEmpty ? null : _latestText,
      error: _recognitionError ?? conversionError,
    );
  }

  @override
  Future<void> cancel() async {
    await _transcriptSubscription?.cancel();
    _transcriptSubscription = null;
    _phraseId = null;
    await _stt.cancel();
  }

  @override
  Future<void> dispose() async {
    await _transcriptSubscription?.cancel();
    _transcriptSubscription = null;
  }
}
