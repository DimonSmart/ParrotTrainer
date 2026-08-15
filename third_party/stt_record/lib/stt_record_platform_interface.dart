import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'stt_record_method_channel.dart';

abstract class SttRecordPlatform extends PlatformInterface {
  /// Constructs a SttRecordPlatform.
  SttRecordPlatform() : super(token: _token);

  static final Object _token = Object();

  static SttRecordPlatform _instance = MethodChannelSttRecord();

  /// The default instance of [SttRecordPlatform] to use.
  ///
  /// Defaults to [MethodChannelSttRecord].
  static SttRecordPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SttRecordPlatform] when
  /// they register themselves.
  static set instance(SttRecordPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<Map<Object?, Object?>> get transcripts {
    throw UnimplementedError('transcripts has not been implemented.');
  }

  Future<bool> hasPermission() {
    throw UnimplementedError('hasPermission() has not been implemented.');
  }

  Future<bool> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  Future<void> start({
    required String localeId,
    required bool partialResults,
    bool enableSystemNotification = false,
    String systemNotificationTitle = 'Recording',
    String systemNotificationBody = 'Recording is running',
    bool enableSystemNotificationActionPause = true,
    bool enableSystemNotificationActionStop = true,
  }) {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// Pauses the current session (recording + recognition) without finalizing.
  ///
  /// Native implementations should keep the current WAV file open so a later
  /// [resume] continues writing into the same file.
  Future<void> pause() {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Resumes a previously paused session.
  Future<void> resume() {
    throw UnimplementedError('resume() has not been implemented.');
  }

  Future<Map<Object?, Object?>> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  Future<void> cancel() {
    throw UnimplementedError('cancel() has not been implemented.');
  }

  /// Returns the current microphone amplitude while recording.
  ///
  /// Native implementations should return a best-effort normalized value in
  /// the range `[0.0, 1.0]`.
  Future<double> getAmplitude() {
    throw UnimplementedError('getAmplitude() has not been implemented.');
  }

  /// Returns supported locale IDs for speech recognition.
  ///
  /// Each item is a map with:
  /// - `localeId`: BCP-47 tag such as `vi-VN`, `en-US`
  /// - `name`: localized display name (best-effort)
  Future<List<Map<Object?, Object?>>> getLocales() {
    throw UnimplementedError('getLocales() has not been implemented.');
  }
}
