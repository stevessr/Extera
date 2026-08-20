import 'package:flutter/foundation.dart';


import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/web_api/web_api.dart';

(Uri redirectUrl, String urlScheme) calcRedirectUrl({
  bool withAuthHtmlPath = false,
}) {
  var redirectUrl = kIsWeb
      ? currentPageUrl()!
      : (PlatformInfos.isMobile || PlatformInfos.isMacOS)
      ? Uri.parse('${AppConfig.appSsoUrlScheme.toLowerCase()}://login/login')
      : Uri.parse('http://localhost:3001/login');

  if (kIsWeb && withAuthHtmlPath) {
    redirectUrl = redirectUrl.resolveUri(Uri(pathSegments: ['auth.html']));
  }

  final urlScheme =
      (PlatformInfos.isMobile || PlatformInfos.isWeb || PlatformInfos.isMacOS)
      ? AppConfig.appSsoUrlScheme
      : 'http://localhost:3001';

  return (redirectUrl, urlScheme);
}
