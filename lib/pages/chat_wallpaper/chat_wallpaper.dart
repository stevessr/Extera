import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';

import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'chat_wallpaper_view.dart';

class ChatWallpaperPage extends StatefulWidget {
  final String roomId;

  const ChatWallpaperPage({required this.roomId, super.key});

  @override
  ChatWallpaperController createState() => ChatWallpaperController();
}

class ChatWallpaperController extends State<ChatWallpaperPage> {
  String get roomId => widget.roomId;

  /// The wallpaper this room renders, which is the global one as long as the
  /// room has none of its own.
  late WallpaperConfig config = wallpaperConfigFor(roomId);

  /// Whether the room overrides the global wallpaper.
  bool get isRoomSpecific => config.isRoomSpecific;

  /// Whether the room deliberately shows no wallpaper.
  bool get isHidden => config.source == wallpaperNone;

  double _pendingOpacity = 0;
  double _pendingBlur = 0;

  double get opacity => _pendingOpacity;
  double get blur => _pendingBlur;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      config = wallpaperConfigFor(roomId);
      _pendingOpacity = config.opacity;
      _pendingBlur = config.blur;
    });
  }

  void setWallpaper() async {
    final picked = await selectFiles(context, type: FileType.image);
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final raw = await file.readAsBytes();
        final compressed = await compressWallpaperBytes(raw);
        await saveWallpaper(roomId: roomId, bytes: compressed);
      },
    );
    if (mounted) _reload();
  }

  /// Drops the room specific wallpaper, so the chat follows the global one
  /// again.
  void useGlobalWallpaper() async {
    await deleteWallpaper(roomId: roomId);
    if (mounted) _reload();
  }

  /// Shows no wallpaper in this room, even though a global one is set.
  void hideWallpaper() async {
    await setRoomWallpaperToNone(roomId);
    if (mounted) _reload();
  }

  void updateOpacity(double value) => setState(() {
    _pendingOpacity = value;
  });

  void saveOpacity(double value) async {
    await setWallpaperOpacity(roomId: roomId, opacity: value);
    if (mounted) _reload();
  }

  void updateBlur(double value) => setState(() {
    _pendingBlur = value;
  });

  void saveBlur(double value) async {
    await setWallpaperBlur(roomId: roomId, blur: value);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => ChatWallpaperView(this);
}
