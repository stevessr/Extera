import 'dart:io';

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/size_string.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/utils/web_api/web_api.dart';

extension MatrixFileExtension on MatrixFile {
  void save(BuildContext context) async {
    if (PlatformInfos.isWeb) {
      _webDownload();
      return;
    }

    final String? downloadPath;
    if (!PlatformInfos.isMobile) {
      downloadPath = (await getSaveLocation(
        suggestedName: name,
        confirmButtonText: L10n.of(context).saveFile,
      ))?.path;
    } else {
      downloadPath = (await FilePicker.saveFile(
        dialogTitle: L10n.of(context).saveFile,
        fileName: name,
        type: filePickerFileType,
        bytes: bytes,
      ))?.toString();
    }
    final savedPath = downloadPath;
    if (savedPath == null) return;

    if (PlatformInfos.isDesktop) {
      final result = await showFutureLoadingDialog(
        context: context,
        future: () => File(savedPath).writeAsBytes(bytes),
      );
      if (result.error != null) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.of(context).fileHasBeenSavedAt(savedPath)),
        showCloseIcon: true,
      ),
    );
  }

  FileType get filePickerFileType {
    if (this is MatrixImageFile) return FileType.image;
    if (this is MatrixAudioFile) return FileType.audio;
    if (this is MatrixVideoFile) return FileType.video;
    return FileType.any;
  }

  void _webDownload() {
    downloadBytes(bytes, name: name, mimeType: mimeType);
  }

  void share(BuildContext context) async {
    // Workaround for iPad from
    // https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus#ipad
    final box = context.findRenderObject() as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return;
  }

  MatrixFile get detectFileType {
    if (msgType == MessageTypes.Image) {
      return MatrixImageFile(bytes: bytes, name: name);
    }
    if (msgType == MessageTypes.Video) {
      return MatrixVideoFile(bytes: bytes, name: name);
    }
    if (msgType == MessageTypes.Audio) {
      return MatrixAudioFile(bytes: bytes, name: name);
    }
    return this;
  }

  String get sizeString => size.sizeString;
}

extension MatrixImageFileShrinkExtension on MatrixImageFile {
  /// Shrinks the image to [maxDimension], but falls back to the original
  /// if shrinking fails or the result is not smaller than the source.
  Future<MatrixImageFile> shrinkWithSizeCheck({
    required int maxDimension,
    required Client client,
  }) async {
    try {
      final shrunk = await MatrixImageFile.shrink(
        bytes: bytes,
        name: name,
        maxDimension: maxDimension,
        mimeType: mimeType,
        customImageResizer: client.customImageResizer,
        nativeImplementations: client.nativeImplementations,
      );
      if (shrunk.bytes.length >= bytes.length) {
        Logs().i(
          'Shrunk image (${shrunk.bytes.length} bytes) is not smaller than '
          'original (${bytes.length} bytes), sending original',
        );
        return this;
      }
      return shrunk;
    } catch (e, s) {
      Logs().w('Unable to shrink image, sending original', e, s);
      return this;
    }
  }
}
