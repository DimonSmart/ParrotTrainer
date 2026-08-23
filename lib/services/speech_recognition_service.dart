import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stt_record/stt_record.dart';

import 'wav_audio_validator.dart';

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

abstract interface class CoordinatedSpeechSession {
  Stream<SttRecordTranscript> get transcripts;
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> start({required String localeId});
  Future<String> stop();
  Future<void> cancel();
}

class SttRecordSession implements CoordinatedSpeechSession {
  SttRecordSession({SttRecord? stt}) : _stt = stt ?? SttRecord();

  final SttRecord _stt;

  @override
  Stream<SttRecordTranscript> get transcripts => _stt.transcripts;

  @override
  Future<bool> hasPermission() => _stt.hasPermission();

  @override
  Future<bool> requestPermission() => _stt.requestPermission();

  @override
  Future<void> start({required String localeId}) =>
      _stt.start(localeId: localeId, partialResults: true);

  @override
  Future<String> stop() async => (await _stt.stop()).audioPath;

  @override
  Future<void> cancel() => _stt.cancel();
}

class EmptyAudioRecordingException implements Exception {
  const EmptyAudioRecordingException();
}

/// Uses one native microphone session for both recording and system speech
/// recognition, so the recognizer never competes with a second recorder.
class SystemSpeechRecognitionService implements SpeechRecognitionService {
  SystemSpeechRecognitionService({CoordinatedSpeechSession? session})
    : _session = session ?? SttRecordSession();

  final CoordinatedSpeechSession _session;
  StreamSubscription<SttRecordTranscript>? _transcriptSubscription;
  String? _phraseId;
  String _latestText = '';
  Object? _recognitionError;
  static const _audioChannel = MethodChannel('parrot_trainer/audio');

  @override
  Future<bool> isAvailable() async =>
      await _isPlatformSupported() && await _session.hasPermission();

  @override
  Future<void> start(String phraseId) async {
    if (!await _isPlatformSupported()) {
      throw UnsupportedError(
        'Coordinated speech recognition requires Android 13 or newer',
      );
    }
    if (!await _session.requestPermission()) {
      throw StateError('Speech recognition permission was not granted');
    }
    _phraseId = phraseId;
    _latestText = '';
    _recognitionError = null;
    await _transcriptSubscription?.cancel();
    _transcriptSubscription = _session.transcripts.listen(
      (result) {
        final text = result.text.trim();
        debugPrint(
          'STT Dart transcript: final=${result.isFinal}, text="$text"',
        );
        if (text.isNotEmpty) _latestText = text;
      },
      onError: (Object error) {
        debugPrint('STT Dart error: $error');
        _recognitionError = error;
      },
    );
    try {
      await _session.start(
        localeId: PlatformDispatcher.instance.locale.toLanguageTag(),
      );
    } catch (_) {
      await _cleanupSession();
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
    String? recognizedText;
    Object? recognitionError;
    var stopped = false;
    try {
      sourcePath = await _session.stop();
      stopped = true;
      recognizedText = _latestText.isEmpty ? null : _latestText;
      recognitionError = _recognitionError;
      debugPrint(
        'STT stop snapshot: text="${recognizedText ?? ''}", error=$recognitionError',
      );
    } finally {
      await _cleanupSession(cancelNative: !stopped);
    }

    final source = File(sourcePath);
    if (!await hasWavAudioPayload(source)) {
      await _deleteIfExists(source);
      throw const EmptyAudioRecordingException();
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
        debugPrint('Audio conversion failed, using WAV: $error');
        if (await m4aDestination.exists()) await m4aDestination.delete();
        if (await wavDestination.exists()) await wavDestination.delete();
        persisted = await File(sourcePath).copy(wavDestination.path);
      }
    } else {
      if (await wavDestination.exists()) await wavDestination.delete();
      persisted = await File(sourcePath).copy(wavDestination.path);
    }
    debugPrint(
      'STT result: text="${recognizedText ?? ''}", audioPath=${persisted.path}, '
      'error=$recognitionError',
    );
    return SpeechRecognitionResult(
      audioPath: persisted.path,
      text: recognizedText,
      error: recognitionError,
    );
  }

  @override
  Future<void> cancel() async {
    await _cleanupSession();
  }

  Future<void> _cleanupSession({bool cancelNative = true}) async {
    await _transcriptSubscription?.cancel();
    _transcriptSubscription = null;
    _phraseId = null;
    _latestText = '';
    _recognitionError = null;
    if (!cancelNative) return;
    try {
      await _session.cancel();
    } catch (_) {
      // Native cleanup is best-effort and must remain safe to repeat.
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> dispose() => _cleanupSession();
}
