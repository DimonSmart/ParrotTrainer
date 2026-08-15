// ignore_for_file: always_put_control_body_on_new_line

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'stt_record_platform_interface.dart';

/// An implementation of [SttRecordPlatform] that uses method channels.
class MethodChannelSttRecord extends SttRecordPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('stt_record/methods');

  @visibleForTesting
  final eventChannel = const EventChannel('stt_record/events');

  Stream<Map<Object?, Object?>>? _transcripts;

  @override
  Stream<Map<Object?, Object?>> get transcripts {
    return _transcripts ??= eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return event.cast<Object?, Object?>();
      }
      // Backwards/defensive: allow native side to emit a bare string.
      if (event is String) {
        return <Object?, Object?>{'text': event, 'isFinal': false};
      }
      return const <Object?, Object?>{'text': '', 'isFinal': false};
    });
  }

  @override
  Future<bool> hasPermission() async {
    return (await methodChannel.invokeMethod<bool>('hasPermission')) ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    return (await methodChannel.invokeMethod<bool>('requestPermission')) ??
        false;
  }

  @override
  Future<void> start({
    required String localeId,
    required bool partialResults,
    bool enableSystemNotification = false,
    String systemNotificationTitle = 'Recording',
    String systemNotificationBody = 'Recording is running',
    bool enableSystemNotificationActionPause = false,
    bool enableSystemNotificationActionStop = false,
  }) {
    return methodChannel.invokeMethod<void>('start', <String, Object?>{
      'localeId': localeId,
      'partialResults': partialResults,
      'enableSystemNotification': enableSystemNotification,
      'systemNotificationTitle': systemNotificationTitle,
      'systemNotificationBody': systemNotificationBody,
      'enableSystemNotificationActionPause':
          enableSystemNotificationActionPause,
      'enableSystemNotificationActionStop': enableSystemNotificationActionStop,
    });
  }

  @override
  Future<void> pause() {
    return methodChannel.invokeMethod<void>('pause');
  }

  @override
  Future<void> resume() {
    return methodChannel.invokeMethod<void>('resume');
  }

  @override
  Future<Map<Object?, Object?>> stop() async {
    final map = await methodChannel.invokeMethod<Map>('stop');
    if (map == null) {
      throw StateError('stop() returned null');
    }
    return map.cast<Object?, Object?>();
  }

  @override
  Future<void> cancel() {
    return methodChannel.invokeMethod<void>('cancel');
  }

  @override
  Future<double> getAmplitude() async {
    final value = await methodChannel.invokeMethod<num>('getAmplitude');
    return (value ?? 0).toDouble();
  }

  @override
  Future<List<Map<Object?, Object?>>> getLocales() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final bool isPermitted = await hasPermission();
      if (!isPermitted) {
        final bool granted =
            await methodChannel.invokeMethod<bool>(
              'requestPermission',
              <String, Object?>{'onlyRecordAudio': true},
            ) ??
            false;
        if (!granted) {
          return const <Map<Object?, Object?>>[];
        }
      }
    }

    final raw = await methodChannel.invokeMethod<List>('getLocales');
    if (raw == null) return const <Map<Object?, Object?>>[];
    return raw
        .whereType<Map>()
        .map((e) => e.cast<Object?, Object?>())
        .toList(growable: false);
  }
}
