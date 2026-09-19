import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/svg_image.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  test('detects plain SVG and XML-declared SVG', () {
    expect(
      isSvgImage(_bytes('<svg xmlns="http://www.w3.org/2000/svg"/>')),
      isTrue,
    );
    expect(
      isSvgImage(
        _bytes(
          '\uFEFF  <?xml version="1.0" encoding="UTF-8"?>\n'
          '<!-- icon -->\n'
          '<svg viewBox="0 0 24 24"><path d="M0 0"/></svg>',
        ),
      ),
      isTrue,
    );
    expect(
      isSvgImage(_bytes('<!DOCTYPE svg><svg xmlns="http://www.w3.org/2000/svg"/>')),
      isTrue,
    );
  });

  test('does not route raster thumbnails or unrelated XML into the SVG parser', () {
    expect(isSvgImage(Uint8List(0)), isFalse);
    expect(
      isSvgImage(
        Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      isFalse,
    );
    expect(isSvgImage(_bytes('<html><svg></svg></html>')), isFalse);
    expect(isSvgImage(_bytes('<?xml version="1.0"?><root/>')), isFalse);
    expect(isSvgImage(_bytes('<svg-not-an-svg/>')), isFalse);
  });
}
