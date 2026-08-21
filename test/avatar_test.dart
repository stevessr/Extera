import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/mxc_image.dart';

/// Regression guard for animated avatars: [Avatar] must forward the
/// `allowAnimatedAvatars` setting to [MxcImage] as the `animated` flag (so the
/// media server returns animated thumbnails) and must include the flag in the
/// in-memory cache key (so toggling the setting does not serve a stale static
/// thumbnail). See `lib/widgets/avatar.dart`.
void main() {
  late MatrixSdkDatabase database;
  late Client client;

  setUpAll(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    database = await MatrixSdkDatabase.init(
      'avatar_test_${DateTime.now().microsecondsSinceEpoch}',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('avatar_test', database: database);
  });

  tearDownAll(() => database.delete());

  // A non-null client keeps MxcImage._load from reaching Matrix.of(context).
  // mxContent == null makes _load return before any network/database call, so
  // the wiring is inspected deterministically without pumping async loads.
  Future<void> pumpAvatar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Avatar(mxContent: null, name: 'Alice', client: client),
      ),
    );
  }

  testWidgets('forwards animated=true and an animated cache key', (
    tester,
  ) async {
    await AppSettings.allowAnimatedAvatars.setItem(true);
    await pumpAvatar(tester);

    final image = tester.widget<MxcImage>(find.byType(MxcImage));
    expect(image.animated, isTrue, reason: 'animated flag must mirror setting');
    expect(
      image.cacheKey,
      endsWith('_anim'),
      reason: 'cache key must differ from the static path',
    );
  });

  testWidgets('forwards animated=false and a static cache key', (tester) async {
    await AppSettings.allowAnimatedAvatars.setItem(false);
    await pumpAvatar(tester);

    final image = tester.widget<MxcImage>(find.byType(MxcImage));
    expect(
      image.animated,
      isFalse,
      reason: 'animated flag must mirror setting',
    );
    expect(
      image.cacheKey,
      isNot(endsWith('_anim')),
      reason: 'static path must not collide with the animated cache entry',
    );
  });
}
