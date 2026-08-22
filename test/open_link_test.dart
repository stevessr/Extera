import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/url_launcher.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingPlatform extends UrlLauncherPlatform {
  String? lastUrl;
  PreferredLaunchMode? lastMode;

  @override
  LinkDelegate get linkDelegate => throw UnimplementedError();

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastUrl = url;
    lastMode = options.mode;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openLink dispatches through the system link resolver', () async {
    final platform = _RecordingPlatform();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = platform;
    addTearDown(() => UrlLauncherPlatform.instance = previous);

    await openLink('https://example.com/some/path?x=1');

    expect(platform.lastUrl, 'https://example.com/some/path?x=1');
    // externalApplication maps to a plain ACTION_VIEW intent on Android, so a
    // verified app link is opened by its registered app instead of a browser.
    expect(platform.lastMode, PreferredLaunchMode.externalApplication);
  });
}
