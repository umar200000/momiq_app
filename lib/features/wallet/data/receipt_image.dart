import 'dart:typed_data';
import 'dart:ui' as ui;

/// Apply upload bounds before retaining evidence in the encrypted draft.
Future<void> validateReceiptImage(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) {
    throw const FormatException('size');
  }
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71;
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  final webp =
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  if (!png && !jpeg && !webp) throw const FormatException('format');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width > 8192 ||
        descriptor.height > 8192 ||
        descriptor.width * descriptor.height > 12000000) {
      throw const FormatException('dimensions');
    }
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount != 1) throw const FormatException('animation');
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
