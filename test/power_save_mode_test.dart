import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/utils/power_save_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('power saver temporarily disables expensive visual features', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);

    await AppSettings.animatedEmoji.setItem(true);
    await AppSettings.autoplayImages.setItem(true);
    await AppSettings.enableChatFrostedGlass.setItem(true);

    PowerSaveMode.enabled.value = false;
    expect(AppSettings.animatedEmoji.value, isTrue);
    expect(AppSettings.autoplayImages.value, isTrue);
    expect(AppSettings.enableChatFrostedGlass.value, isTrue);

    PowerSaveMode.enabled.value = true;
    expect(AppSettings.animatedEmoji.value, isFalse);
    expect(AppSettings.autoplayImages.value, isFalse);
    expect(AppSettings.enableChatFrostedGlass.value, isFalse);

    // The override is effective-only: leaving power saver restores what the
    // user configured instead of permanently changing SharedPreferences.
    expect(AppSettings.store.getBool(AppSettings.animatedEmoji.key), isTrue);
    expect(AppSettings.store.getBool(AppSettings.autoplayImages.key), isTrue);
    expect(
      AppSettings.store.getBool(AppSettings.enableChatFrostedGlass.key),
      isTrue,
    );

    PowerSaveMode.enabled.value = false;
    expect(AppSettings.animatedEmoji.value, isTrue);
    expect(AppSettings.autoplayImages.value, isTrue);
    expect(AppSettings.enableChatFrostedGlass.value, isTrue);
  });
}
