import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/config/unicode_fallback_fonts.dart';
import 'package:extera_next/utils/unicode_font_loader.dart';
import 'package:extera_next/widgets/unicode_font_fallback_scope.dart';

class _FakeCoverageProbe implements UnicodeGlyphCoverageProbe {
  _FakeCoverageProbe({Set<int>? missing}) : missing = missing ?? <int>{};

  final Set<int> missing;
  final List<Set<int>> calls = <Set<int>>[];

  @override
  Future<Set<int>> missingCodePoints(Set<int> codePoints) async {
    calls.add(Set<int>.of(codePoints));
    return codePoints.intersection(missing);
  }
}

void main() {
  test('generated range index is sorted, disjoint, and references assets', () {
    var previousEnd = -1;
    for (final range in debugUnicodeFallbackFontRangeIndex) {
      expect(range.$1, greaterThan(previousEnd));
      expect(range.$2, greaterThanOrEqualTo(range.$1));
      expect(
        range.$3,
        inInclusiveRange(0, kUnicodeFallbackFontAssets.length - 1),
      );
      previousEnd = range.$2;
    }

    for (final asset in kUnicodeFallbackFontAssets) {
      expect(File(asset.asset).existsSync(), isTrue, reason: asset.asset);
    }
  });

  test('code points resolve to the exact tree-shaken chunk', () {
    UnicodeFallbackFontAsset assetFor(int codePoint) =>
        kUnicodeFallbackFontAssets[unicodeFallbackAssetIndexForCodePoint(
          codePoint,
        )!];

    expect(assetFor(0x4E2D).family, 'Plangothic P2 u00295');
    expect(assetFor(0x1FAEB).family, 'UFSTemp Alpha u16D80');
    expect(assetFor(0x30EDE).family, 'Plangothic P2 u30803');
    expect(unicodeFallbackAssetIndexForCodePoint(0x10FFFF), isNull);
  });

  test('system-supported characters do not load bundled fonts', () async {
    final probe = _FakeCoverageProbe();
    final loaded = <UnicodeFallbackFontAsset>[];
    final loader = UnicodeFontLoader(
      coverageProbe: probe,
      fontAssetLoader: (asset) async => loaded.add(asset),
    );

    await loader.ensureFontsForText('中文');

    expect(probe.calls, [
      <int>{0x4E2D, 0x6587},
    ]);
    expect(loaded, isEmpty);
  });

  test(
    'missing characters load only their assets and deduplicate chunks',
    () async {
      final probe = _FakeCoverageProbe(missing: <int>{0x4E2D, 0x6587, 0x30EDE});
      final loaded = <UnicodeFallbackFontAsset>[];
      final loader = UnicodeFontLoader(
        coverageProbe: probe,
        fontAssetLoader: (asset) async => loaded.add(asset),
      );

      await loader.ensureFontsForText('中文𰻞');
      await loader.ensureFontsForText('中文𰻞');

      expect(loaded.map((asset) => asset.family), <String>[
        'Plangothic P2 u00295',
        'Plangothic P2 u30803',
      ]);
      expect(probe.calls, hasLength(1));
    },
  );

  test('printable ASCII bypasses both probe and asset loader', () async {
    final probe = _FakeCoverageProbe(missing: <int>{0x41});
    final loaded = <UnicodeFallbackFontAsset>[];
    final loader = UnicodeFontLoader(
      coverageProbe: probe,
      fontAssetLoader: (asset) async => loaded.add(asset),
    );

    await loader.ensureFontsForText('Hello, Matrix 123!');

    expect(probe.calls, isEmpty);
    expect(loaded, isEmpty);
  });

  testWidgets('scope scans visible text but not offstage text', (tester) async {
    final probe = _FakeCoverageProbe();
    final loader = UnicodeFontLoader(
      coverageProbe: probe,
      fontAssetLoader: (_) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnicodeFontFallbackScope(
          enabled: true,
          loader: loader,
          child: const Column(
            children: <Widget>[
              Text('🫫'),
              Offstage(offstage: true, child: Text('𰻞')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(probe.calls.expand((call) => call), contains(0x1FAEB));
    expect(probe.calls.expand((call) => call), isNot(contains(0x30EDE)));
  });

  testWidgets('disabled scope performs no probe', (tester) async {
    final probe = _FakeCoverageProbe();
    final loader = UnicodeFontLoader(
      coverageProbe: probe,
      fontAssetLoader: (_) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnicodeFontFallbackScope(
          enabled: false,
          loader: loader,
          child: const Text('🫫'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(probe.calls, isEmpty);
  });
}
