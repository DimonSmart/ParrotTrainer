import 'dart:io';
import 'package:just_audio/just_audio.dart';

abstract interface class RecordedPhrasePlayer { Future<bool> playIfAvailable(String? path); Future<void> stop(); }
class LocalRecordedPhrasePlayer implements RecordedPhrasePlayer {
  AudioPlayer? _player;
  @override
  Future<bool> playIfAvailable(String? path) async {
    if (path == null || !await File(path).exists()) return false;
    try { final player = _player ??= AudioPlayer(); await player.setFilePath(path); await player.play(); return true; } catch (_) { return false; }
  }
  @override Future<void> stop() async => _player == null ? null : _player!.stop();
}
