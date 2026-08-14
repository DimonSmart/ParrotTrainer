import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/services/wav_audio_validator.dart';

void main() {
  test('rejects a WAV with only a header', () async {
    final file = await _temporaryWav(const []);

    expect(await hasWavAudioPayload(file), isFalse);

    await file.delete();
  });

  test('accepts a WAV with a meaningful PCM payload', () async {
    final file = await _temporaryWav(
      List.filled(minimumWavAudioPayloadBytes, 1),
    );

    expect(await hasWavAudioPayload(file), isTrue);

    await file.delete();
  });
}

Future<File> _temporaryWav(List<int> payload) async {
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}parrot-${DateTime.now().microsecondsSinceEpoch}.wav',
  );
  final bytes = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add(_uint32(36 + payload.length))
    ..add('WAVE'.codeUnits)
    ..add('fmt '.codeUnits)
    ..add(_uint32(16))
    ..add(List<int>.filled(16, 0))
    ..add('data'.codeUnits)
    ..add(_uint32(payload.length))
    ..add(payload);
  await file.writeAsBytes(bytes.toBytes());
  return file;
}

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];
