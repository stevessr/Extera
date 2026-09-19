import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Inspect only the beginning of the payload. SVG is XML, not a bitmap, and
// cannot be decoded by Flutter's Image.memory. Sniff the actual bytes rather
// than the advertised MIME type: a homeserver's SVG thumbnail may be a PNG.
final RegExp _svgDocumentStart = RegExp(
  r'^\s*(?:<\?xml[^>]*\?>\s*|<!--[\s\S]*?-->\s*|<!DOCTYPE[^>]*>\s*)*<svg(?=[\s/>])',
  caseSensitive: false,
);

bool isSvgImage(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  // Raster images and most other media never start with an XML tag. Avoid
  // allocating or parsing their payload on every timeline rebuild.
  var offset = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF
      ? 3
      : 0;
  while (offset < bytes.length &&
      (bytes[offset] == 0x20 ||
          bytes[offset] == 0x09 ||
          bytes[offset] == 0x0A ||
          bytes[offset] == 0x0D)) {
    offset++;
  }
  if (offset == bytes.length || bytes[offset] != 0x3C) return false;

  final prefix = utf8.decode(
    bytes.sublist(0, min(bytes.length, 8192)),
    allowMalformed: true,
  );
  return _svgDocumentStart.hasMatch(prefix.replaceFirst('\uFEFF', ''));
}
