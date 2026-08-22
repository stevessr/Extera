import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';
import 'package:extera_next/utils/url_launcher.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';

class ErrorReporter {
  final BuildContext? context;
  final String? message;

  const ErrorReporter(this.context, [this.message]);

  static const Set<String> ingoredTypes = {
    "IOException",
    "ClientException",
    "SocketException",
    "TlsException",
    "HandshakeException",
  };

  void onErrorCallback(Object error, [StackTrace? stackTrace]) {
    if (ingoredTypes.contains(error.runtimeType.toString())) return;
    Logs().e(message ?? 'Error caught', error, stackTrace);
    final text = '$error\n${stackTrace ?? ''}';
    return _onErrorCallback(text);
  }

  void _onErrorCallback(String text) async {
    await showAdaptiveDialog(
      context: context!,
      useRootNavigator: false,
      builder: (context) => AlertDialog.adaptive(
        title: Text(L10n.of(context).reportErrorDescription),
        content: SizedBox(
          height: 256,
          width: 256,
          child: SingleChildScrollView(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppSettings.monospaceFont.value,
                fontFamilyFallback: AppSettings.monospaceFallbackFonts.value
                    .split(','),
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24.0),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.of(context).close),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24.0),
              ),
            ),
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: Text(L10n.of(context).copy),
          ),
          FilledButton(
            onPressed: () => openLink(
              AppConfig.newIssueUrl
                  .resolveUri(
                    Uri(queryParameters: {'template': 'bug_report.yaml'}),
                  )
                  .toString(),
            ),
            child: Text(L10n.of(context).report),
          ),
        ],
      ),
    );
  }
}
