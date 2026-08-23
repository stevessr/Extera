import 'package:flutter_test/flutter_test.dart';
import 'package:extera_next/utils/avatar_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AvatarHistory records, dedupes and caps entries', () async {
    SharedPreferences.setMockInitialValues({});
    await AvatarHistory.record('mxc://example.org/a');
    await AvatarHistory.record('mxc://example.org/b');
    await AvatarHistory.record('not-an-mxc');
    await AvatarHistory.record('mxc://example.org/a');
    expect(await AvatarHistory.load(), [
      'mxc://example.org/a',
      'mxc://example.org/b',
    ]);
  });
}
