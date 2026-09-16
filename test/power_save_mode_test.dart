import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/power_save_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'power saver temporarily disables expensive visual and motion features',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);

      await AppSettings.animatedEmoji.setItem(true);
      await AppSettings.autoplayImages.setItem(true);
      await AppSettings.enableChatFrostedGlass.setItem(true);
      await AppSettings.enableGradient.setItem(true);
      await AppSettings.wallpaperBlur.setItem(18.0);

      PowerSaveMode.enabled.value = false;
      expect(AppSettings.animatedEmoji.value, isTrue);
      expect(AppSettings.autoplayImages.value, isTrue);
      expect(AppSettings.enableChatFrostedGlass.value, isTrue);
      expect(AppSettings.enableGradient.value, isTrue);
      expect(AppSettings.wallpaperBlur.value, 18.0);
      expect(
        FluffyThemes.effectiveAnimationDuration,
        FluffyThemes.animationDuration,
      );
      expect(
        FluffyThemes.reduceMotionDuration(const Duration(milliseconds: 200)),
        const Duration(milliseconds: 200),
      );

      PowerSaveMode.enabled.value = true;
      expect(AppSettings.animatedEmoji.value, isFalse);
      expect(AppSettings.autoplayImages.value, isFalse);
      expect(AppSettings.enableChatFrostedGlass.value, isFalse);
      expect(AppSettings.enableGradient.value, isFalse);
      expect(AppSettings.wallpaperBlur.value, 0.0);
      expect(FluffyThemes.effectiveAnimationDuration, Duration.zero);
      expect(
        FluffyThemes.reduceMotionDuration(const Duration(milliseconds: 200)),
        Duration.zero,
      );

      // The override is effective-only: leaving power saver restores what the
      // user configured instead of permanently changing SharedPreferences.
      expect(AppSettings.store.getBool(AppSettings.animatedEmoji.key), isTrue);
      expect(AppSettings.store.getBool(AppSettings.autoplayImages.key), isTrue);
      expect(
        AppSettings.store.getBool(AppSettings.enableChatFrostedGlass.key),
        isTrue,
      );
      expect(AppSettings.store.getBool(AppSettings.enableGradient.key), isTrue);
      expect(AppSettings.store.getDouble(AppSettings.wallpaperBlur.key), 18.0);

      PowerSaveMode.enabled.value = false;
      expect(AppSettings.animatedEmoji.value, isTrue);
      expect(AppSettings.autoplayImages.value, isTrue);
      expect(AppSettings.enableChatFrostedGlass.value, isTrue);
      expect(AppSettings.enableGradient.value, isTrue);
      expect(AppSettings.wallpaperBlur.value, 18.0);
      expect(
        FluffyThemes.effectiveAnimationDuration,
        FluffyThemes.animationDuration,
      );
    },
  );
}
