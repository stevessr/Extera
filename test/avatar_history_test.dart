import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/utils/avatar_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recording into an empty history does not throw', () async {
    // Regression: reading the absent key used to fall back to an
    // unmodifiable const list, so the very first record() crashed with an
    // UnsupportedError and the history could never grow.
    SharedPreferences.setMockInitialValues({});
    await AvatarHistory.record('mxc://example.org/abc');
    expect(await AvatarHistory.load(), ['mxc://example.org/abc']);
  });

  test('deduplicates and keeps newest first', () async {
    SharedPreferences.setMockInitialValues({
      'xyz.extera.avatar_history': <String>['mxc://a', 'mxc://b'],
    });
    await AvatarHistory.record('mxc://b');
    expect(await AvatarHistory.load(), ['mxc://b', 'mxc://a']);
  });

  test('rejects non-mxc URIs', () async {
    SharedPreferences.setMockInitialValues({});
    await AvatarHistory.record('https://example.org/avatar.png');
    expect(await AvatarHistory.load(), isEmpty);
  });

  test('filters stale invalid and duplicate persisted entries', () async {
    SharedPreferences.setMockInitialValues({
      'xyz.extera.avatar_history': <String>[
        'https://example.org/avatar.png',
        'mxc://example.org/a',
        'mxc://example.org/a',
        'not a uri',
        'mxc://example.org/b',
      ],
    });
    expect(await AvatarHistory.load(), [
      'mxc://example.org/a',
      'mxc://example.org/b',
    ]);
  });

  test('recordUri ignores null and records Matrix content URIs', () async {
    SharedPreferences.setMockInitialValues({});
    await AvatarHistory.recordUri(null);
    await AvatarHistory.recordUri(Uri.parse('mxc://example.org/current'));
    expect(await AvatarHistory.load(), ['mxc://example.org/current']);
  });

  test('history is capped at 32 entries', () async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 0; i < 40; i++) {
      await AvatarHistory.record('mxc://example.org/$i');
    }
    final history = await AvatarHistory.load();
    expect(history, hasLength(32));
    expect(history.first, 'mxc://example.org/39');
    expect(history.last, 'mxc://example.org/8');
  });
}
