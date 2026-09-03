import 'dart:async';

import 'package:record/record.dart';

class AudioLevelService {
  AudioLevelService({AudioRecorder? recorder}) : _recorder = recorder;

  AudioRecorder? _recorder;
  StreamSubscription<dynamic>? _audioSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final _levels = StreamController<double>.broadcast();
  Future<void> _pendingOperation = Future.value();

  Stream<double> get levels => _levels.stream;
  bool _running = false;

  AudioRecorder get _deviceRecorder => _recorder ??= AudioRecorder();

  Future<bool> start() => _enqueue(_start);

  Future<bool> _start() async {
    if (_running) return true;
    final recorder = _deviceRecorder;
    if (!await recorder.hasPermission()) return false;
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.none,
      ),
    );
    _audioSubscription = stream.listen((_) {});
    _amplitudeSubscription = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amplitude) => _levels.add(amplitude.current));
    _running = true;
    return true;
  }

  Future<void> stop() => _enqueue(_stop);

  Future<void> _stop() async {
    if (!_running) return;
    await _amplitudeSubscription?.cancel();
    await _audioSubscription?.cancel();
    _amplitudeSubscription = null;
    _audioSubscription = null;
    await _recorder?.stop();
    _running = false;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pendingOperation.then((_) => operation());
    _pendingOperation = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> dispose() async {
    await stop();
    await _levels.close();
    await _recorder?.dispose();
  }
}
