// ignore_for_file: always_put_control_body_on_new_line

import 'dart:async';
import 'dart:io';

import 'locale_options_android.dart';
import 'stt_record_platform_interface.dart';

/// Record audio and run speech-to-text in parallel (realtime).
///
/// Usage:
/// - Call [requestPermission] (or handle permissions in your app).
/// - Call [start] to begin.
/// - Listen to [transcripts] for realtime partial/final text.
/// - Call [stop] to finalize and get the recorded audio file path.
class SttRecord {
  SttRecord({SttRecordPlatform? platform})
    : _platform = platform ?? SttRecordPlatform.instance;

  final SttRecordPlatform _platform;

  /// Realtime transcript stream.
  ///
  /// Events contain both partial and final hypotheses.
  Stream<SttRecordTranscript> get transcripts => _platform.transcripts
      .where((e) => !SttRecordSessionState.isStateEvent(e))
      .map(SttRecordTranscript.fromMap);

  /// Session state events (pause/resume on interruption or via [pause]/[resume]).
  Stream<SttRecordSessionState> get sessionStates => _platform.transcripts
      .map(SttRecordSessionState.tryParse)
      .where((e) => e != null)
      .map((e) => e!);

  /// Returns `true` if the required permissions are granted.
  Future<bool> hasPermission() => _platform.hasPermission();

  /// Requests the required permissions.
  ///
  /// On iOS this includes: microphone + speech recognition.
  /// On Android: microphone.
  Future<bool> requestPermission() => _platform.requestPermission();

  /// Starts recording and speech recognition.
  Future<void> start({
    String localeId = 'vi-VN',
    bool partialResults = true,
    bool enableSystemNotification = false,
    String systemNotificationTitle = 'Recording',
    String systemNotificationBody = 'Recording is running',
    bool enableSystemNotificationActionPause = true,
    bool enableSystemNotificationActionStop = false,
  }) {
    return _platform.start(
      localeId: localeId,
      partialResults: partialResults,
      enableSystemNotification: enableSystemNotification,
      systemNotificationTitle: systemNotificationTitle,
      systemNotificationBody: systemNotificationBody,
      enableSystemNotificationActionPause: enableSystemNotificationActionPause,
      enableSystemNotificationActionStop: enableSystemNotificationActionStop,
    );
  }

  /// Pauses the current session (recording + recognition) without finalizing.
  ///
  /// The session can later be continued via [resume].
  Future<void> pause() => _platform.pause();

  /// Resumes a previously paused session.
  Future<void> resume() => _platform.resume();

  /// Stops recording and recognition.
  ///
  /// Returns the audio file path written by the native side.
  Future<SttRecordStopResult> stop() async {
    final map = await _platform.stop();
    return SttRecordStopResult.fromMap(map);
  }

  /// Cancels the current session.
  ///
  /// This is a best-effort cleanup. The recorded file (if any) may be deleted.
  Future<void> cancel() => _platform.cancel();

  /// Returns the current microphone amplitude while recording.
  ///
  /// The returned value is best-effort and normalized to `[0.0, 1.0]`.
  /// When no session is running, native implementations should return `0.0`.
  Future<double> getAmplitude() => _platform.getAmplitude();

  /// Returns supported locale IDs for speech recognition.
  ///
  /// Values are platform-provided BCP-47 tags such as `vi-VN`, `en-US`.
  /// The first item is usually the current/preferred locale when available.
  ///
  /// The returned list includes both `localeId` and a localized display `name`.
  Future<List<SttRecordLocale>> getLocales({
    List<String>? preferLocales,
  }) async {
    if (Platform.isAndroid) {
      final locales = supportedLocalesJson
          .map(
            (e) => SttRecordLocale(
              localeId: e['localeId'] as String,
              name: e['languageName'] as String,
            ),
          )
          .toList();

      final sorted = sortLocales(
        locales,
        preferLocales: preferLocales ?? preferLocalesDefault,
      );

      return sorted;
    }

    final raw = await _platform.getLocales();
    final out = <SttRecordLocale>[];
    final seen = <String>{};

    for (final map in raw) {
      final locale = SttRecordLocale.tryFromMap(map);
      if (locale == null) continue;
      if (!seen.add(locale.localeId)) continue;
      out.add(locale);
    }

    return out;
  }
}

List<SttRecordLocale> sortLocales(
  List<SttRecordLocale> locales, {
  List<String> preferLocales = const ['vi-VN', 'en-US'],
}) {
  final preferred = <SttRecordLocale>[];
  final rest = <SttRecordLocale>[];

  for (final locale in locales) {
    if (preferLocales.contains(locale.localeId)) {
      preferred.add(locale);
    } else {
      rest.add(locale);
    }
  }

  // Giữ đúng thứ tự ưu tiên theo preferLocales
  preferred.sort(
    (a, b) => preferLocales
        .indexOf(a.localeId)
        .compareTo(preferLocales.indexOf(b.localeId)),
  );

  return [...preferred, ...rest];
}

class SttRecordTranscript {
  const SttRecordTranscript({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;

  factory SttRecordTranscript.fromMap(Map<Object?, Object?> map) {
    return SttRecordTranscript(
      text: (map['text'] as String?) ?? '',
      isFinal: (map['isFinal'] as bool?) ?? false,
    );
  }
}

enum SttRecordSessionState {
  paused,
  resumed
  ;

  static bool isStateEvent(Map<Object?, Object?> map) {
    final event = map['event'];
    if (event is String) {
      return event == 'state';
    }
    return map.containsKey('state');
  }

  static SttRecordSessionState? tryParse(Map<Object?, Object?> map) {
    final event = map['event'];
    if (event is String && event != 'state') return null;

    final raw = map['state'];
    if (raw is! String) return null;

    switch (raw) {
      case 'paused':
        return SttRecordSessionState.paused;
      case 'resumed':
        return SttRecordSessionState.resumed;
    }
    return null;
  }
}

class SttRecordStopResult {
  const SttRecordStopResult({
    required this.audioPath,
  });

  final String audioPath;

  factory SttRecordStopResult.fromMap(Map<Object?, Object?> map) {
    final audioPath = map['audioPath'] as String?;
    if (audioPath == null || audioPath.isEmpty) {
      throw StateError('Missing "audioPath" in stop() result.');
    }
    return SttRecordStopResult(audioPath: audioPath);
  }
}

class SttRecordLocale {
  const SttRecordLocale({
    required this.localeId,
    required this.name,
  });

  final String localeId;
  final String name;

  static SttRecordLocale? tryFromMap(Map<Object?, Object?> map) {
    final localeId = map['localeId'];
    if (localeId is! String) return null;
    final trimmedId = localeId.trim();
    if (trimmedId.isEmpty) return null;

    final name = map['name'];
    final resolvedName = (name is String && name.trim().isNotEmpty)
        ? name.trim()
        : trimmedId;

    return SttRecordLocale(localeId: trimmedId, name: resolvedName);
  }
}
