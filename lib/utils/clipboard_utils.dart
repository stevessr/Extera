import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

Future<void> writeImageToClipboard(Uint8List bytes) async {
  if (Platform.isWindows || Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
    await Pasteboard.writeImage(bytes);
  } else if (Platform.isLinux) {
    final tempFile = File('${Directory.systemTemp.path}/clipboard_image.png');
    await tempFile.writeAsBytes(bytes);
    try {
      await Process.run('xclip', [
        '-selection', 'clipboard',
        '-t', 'image/png',
        '-i', tempFile.path,
      ]);
    } catch (_) {
      try {
        await Process.run('wl-copy', ['--type', 'image/png', tempFile.path]);
      } catch (_) {}
    }
    await tempFile.delete();
  }
}

Future<Uint8List?> getImageFromClipboardLinux() async {
  final cmds = [
    ['wl-paste', '-t', 'image/png'],
    ['xclip', '-selection', 'clipboard', '-t', 'image/png', '-o'],
    ['xsel', '--clipboard', '--output', '--mime-type', 'image/png'],
  ];

  for (final cmd in cmds) {
    try {
      final result = await Process.run(
        cmd.first,
        cmd.sublist(1),
        stdoutEncoding: null,
      );
      if (result.exitCode != 0) continue;

      final Uint8List stdoutBytes = result.stdout;
      if (stdoutBytes.isNotEmpty) {
        return Uint8List.fromList(stdoutBytes);
      }
    } catch (_) {}
  }
  return null;
}

Future<Uint8List?> getImageFromClipboardWindows() async {
  try {
    final image = await Pasteboard.image;
    if (image != null) {
      return image;
    }
  } catch (_) {}
  return null;
}

Future<Uint8List?> getImageFromClipboardMacOS() async {
  try {
    final image = await Pasteboard.image;
    if (image != null) {
      return image;
    }
  } catch (_) {}
  return null;
}
