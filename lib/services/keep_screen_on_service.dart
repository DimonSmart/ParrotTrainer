import 'package:flutter/services.dart';

abstract interface class KeepScreenOnService {
  Future<void> setEnabled(bool enabled);
}

class AndroidKeepScreenOnService implements KeepScreenOnService {
  static const _channel = MethodChannel('parrot_trainer/screen');

  @override
  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
}
