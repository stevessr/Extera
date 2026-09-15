import 'package:flutter/widgets.dart';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';

import 'package:extera_next/widgets/app_lock.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';

Future<XFile?> selectFile(
  BuildContext context, {
  String? title,
  FileType type = FileType.any,
}) async {
  final result = await AppLock.of(context).pauseWhile(
    showFutureLoadingDialog(
      context: context,
      future: () => FilePicker.pickFile(compressionQuality: 0, type: type),
    ),
  );
  return result.result?.xFile;
}

Future<List<XFile>> selectFiles(
  BuildContext context, {
  String? title,
  FileType type = FileType.any,
}) async {
  final result = await AppLock.of(context).pauseWhile(
    showFutureLoadingDialog(
      context: context,
      future: () => FilePicker.pickFiles(compressionQuality: 0, type: type),
    ),
  );
  return result.result?.map((x) => x.xFile).toList() ?? [];
}
