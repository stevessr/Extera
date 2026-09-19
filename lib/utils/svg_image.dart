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
  final prefix = utf8.decode(
    bytes.sublist(0, min(bytes.length, 8192)),
    allowMalformed: true,
  );
  return _svgDocumentStart.hasMatch(prefix.replaceFirst('\uFEFF', ''));
}
