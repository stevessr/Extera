import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:matrix/matrix.dart';
import 'package:video_compress/video_compress.dart';

import 'package:extera_next/utils/client_manager.dart';
import 'package:extera_next/utils/platform_infos.dart';

extension ResizeImage on XFile {
  static const int max = 1200;
  static const int quality = 40;

  Future<MatrixVideoFile> resizeVideo() async {
    MediaInfo? mediaInfo;
    try {
      if (PlatformInfos.isMobile) {
        // will throw an error e.g. on Android SDK < 18
        mediaInfo = await VideoCompress.compressVideo(path);
      }
    } catch (e, s) {
      Logs().w('Error while compressing video', e, s);
    }

    final compressedFile = mediaInfo?.file;
    Uint8List bytes;
    var width = mediaInfo?.width;
    var height = mediaInfo?.height;
    var duration = mediaInfo?.duration?.round();
    if (compressedFile != null) {
      final compressedBytes = await compressedFile.readAsBytes();
      if (compressedBytes.length < await length()) {
        bytes = compressedBytes;
      } else {
        Logs().i(
          'Compressed video (${compressedBytes.length} bytes) is not smaller '
          'than original (${await length()} bytes), sending original',
        );
        bytes = await readAsBytes();
        width = null;
        height = null;
        duration = null;
      }
    } else {
      bytes = await readAsBytes();
    }

    return MatrixVideoFile(
      bytes: bytes,
      name: name,
      mimeType: mimeType,
      width: width,
      height: height,
      duration: duration,
    );
  }

  Future<MatrixImageFile?> getVideoThumbnail() async {
    if (!PlatformInfos.isMobile) return null;

    try {
      final bytes = await VideoCompress.getByteThumbnail(path);
      if (bytes == null) return null;

      return await MatrixImageFile.create(
        bytes: bytes,
        name: name,
        nativeImplementations: ClientManager.nativeImplementations,
      );
    } catch (e, s) {
      Logs().w('Error while compressing video', e, s);
    }
    return null;
  }
}
