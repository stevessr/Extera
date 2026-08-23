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
}
