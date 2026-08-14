import 'dart:io';
import 'dart:typed_data';

const minimumWavAudioPayloadBytes = 1024;

/// Returns whether [file] is a RIFF/WAV file with a meaningful PCM payload.
Future<bool> hasWavAudioPayload(File file) async {
  if (!await file.exists()) return false;
  final bytes = await file.readAsBytes();
  if (bytes.length < 12 ||
      _ascii(bytes, 0, 'RIFF') == false ||
      _ascii(bytes, 8, 'WAVE') == false) {
    return false;
  }

  final data = ByteData.sublistView(bytes);
  var offset = 12;
  var hasPcmFormat = false;
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset + 4, Endian.little);
    final payloadStart = offset + 8;
    final payloadEnd = payloadStart + length;
    if (payloadEnd > bytes.length) return false;
    if (_ascii(bytes, offset, 'fmt ')) {
      hasPcmFormat = length >= 16;
    } else if (_ascii(bytes, offset, 'data')) {
      return hasPcmFormat && length >= minimumWavAudioPayloadBytes;
    }
    offset = payloadEnd + (length.isOdd ? 1 : 0);
  }
  return false;
}

bool _ascii(Uint8List bytes, int offset, String value) {
  if (offset + value.length > bytes.length) return false;
  for (var index = 0; index < value.length; index++) {
    if (bytes[offset + index] != value.codeUnitAt(index)) return false;
  }
  return true;
}
