import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/pages/chat/events/url_preview_card.dart';

void main() {
  group('UrlPreviewCard.extractSingleLink', () {
    test('accepts a bare link', () {
      final url = UrlPreviewCard.extractSingleLink(
        'https://matrix.org/blog/post',
      );
      expect(url, isNotNull);
      expect(url!.host, 'matrix.org');
    });

    test('accepts a link surrounded by whitespace and newlines', () {
      final url = UrlPreviewCard.extractSingleLink(
        '\n  https://example.com/some/path?q=1  \n',
      );
      expect(url, isNotNull);
      expect(url!.path, '/some/path');
    });

    test('accepts an http link', () {
      expect(UrlPreviewCard.extractSingleLink('http://example.com'), isNotNull);
    });

    test('strips the edited message marker before matching', () {
      final url = UrlPreviewCard.extractSingleLink(
        '* https://example.com/edited',
      );
      expect(url, isNotNull);
      expect(url!.host, 'example.com');
    });

    test('rejects a link with extra text around it', () {
      expect(
        UrlPreviewCard.extractSingleLink('look at https://example.com now'),
        isNull,
      );
      expect(
        UrlPreviewCard.extractSingleLink('https://example.com and more'),
        isNull,
      );
    });

    test('rejects messages without links or with multiple links', () {
      expect(UrlPreviewCard.extractSingleLink('hello world'), isNull);
      expect(
        UrlPreviewCard.extractSingleLink('https://a.example https://b.example'),
        isNull,
      );
    });

    test('rejects non-http schemes and empty input', () {
      expect(UrlPreviewCard.extractSingleLink(''), isNull);
      expect(UrlPreviewCard.extractSingleLink('   '), isNull);
      expect(
        UrlPreviewCard.extractSingleLink('ftp://files.example.com/pub'),
        isNull,
      );
      // A scheme-less domain is not treated as a link.
      expect(UrlPreviewCard.extractSingleLink('example.com'), isNull);
    });
  });
}
