import 'package:flutter/material.dart';

import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:go_router/go_router.dart';

Future<void> restoreBackupFlow(BuildContext context) async {
  final mx = Matrix.of(context);

  final picked = await selectFiles(context);
  final file = picked.firstOrNull;
  if (file == null) return;

  if (!context.mounted) return;

  final result = await showFutureLoadingDialog<bool>(
    context: context,
    future: () async {
      final client = await mx.getLoginClient();
      await client.importDump(String.fromCharCodes(await file.readAsBytes()));
      mx.initMatrix();
      return client.isLogged();
    },
  );

  if (result.result == true && context.mounted) {
    context.go('/rooms');
  }
}
