import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/isrg_x1.dart';
import 'package:extera_next/config/isrg_x2.dart';
import 'package:extera_next/utils/platform_infos.dart';

class CustomHttpClient {
  static HttpClient? customHttpClient() {
    if (PlatformInfos.isWeb) return null;

    final context = SecurityContext.defaultContext;

    if (PlatformInfos.isAndroid) {
      try {
        context.setTrustedCertificatesBytes(utf8.encode(ISRG_X1));
        context.setTrustedCertificatesBytes(utf8.encode(ISRG_X2));
      } on TlsException catch (e) {
        if (e.osError != null &&
            e.osError!.message.contains('CERT_ALREADY_IN_HASH_TABLE')) {
        } else {
          rethrow;
        }
      }
    }

    final client = HttpClient(context: context);

    if (AppSettings.httpProxy.value.isNotEmpty) {
      client.findProxy = (uri) {
        return "PROXY ${AppSettings.httpProxy.value};";
      };
    }

    return client;
  }

  static http.Client createHTTPClient() {
    // On web, IOClient(null) would create HttpClient() from dart:io which
    // crashes on the web platform. Use the default http.Client() instead,
    // which correctly resolves to BrowserClient on web via conditional imports.
    if (kIsWeb) {
      return http.Client();
    }
    return IOClient(customHttpClient());
  }
}
