import 'dart:io';
import 'package:just_audio/just_audio.dart';

abstract interface class RecordedPhrasePlayer {
  Future<bool> playIfAvailable(String? path);
  Future<void> stop();
  Future<void> dispose();
}

class LocalRecordedPhrasePlayer implements RecordedPhrasePlayer {
  AudioPlayer? _player;
  @override
  Future<bool> playIfAvailable(String? path) async {
    if (path == null || !await File(path).exists()) return false;
    try {
      final player = _player ??= AudioPlayer();
      await player.setFilePath(path);
      await player.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
