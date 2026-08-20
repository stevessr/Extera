import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';
import 'package:native_imaging/native_imaging.dart' as native;
import 'package:path_provider/path_provider.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/utils/wallpaper_store/wallpaper_store.dart';

/// Value stored as the wallpaper source on web.
///
/// The image itself lives in IndexedDB, the setting only records that one is
/// set. On native platforms the setting holds the path of the wallpaper file.
const String wallpaperIndexedDbMarker = 'indexeddb:wallpaper';

/// Source value of a room that deliberately shows no wallpaper at all, even
/// though a global one is configured.
const String wallpaperNone = 'none';

/// Maximum edge length of a stored wallpaper.
const int wallpaperMaxDimension = 1920;

/// JPEG quality used when storing a wallpaper.
const int wallpaperJpegQuality = 85;

const double _defaultOpacity = 0.5;
const double _defaultBlur = 0.0;

/// In-memory copies of the wallpapers on web, so that [WallpaperConfig.image]
/// can stay synchronous and be called from `build`.
///
/// Keyed by [WallpaperConfig.storageKey]: the empty string for the global
/// wallpaper, the room id for a room specific one.
final Map<String, Uint8List> _wallpaperBytes = {};

/// Bumped whenever any wallpaper changes, so that open chats can repaint
/// without having to be rebuilt for another reason.
final ValueNotifier<int> wallpaperRevision = ValueNotifier<int>(0);

void _notifyWallpaperChanged() => wallpaperRevision.value++;

String _opacityKey(String roomId) =>
    '${AppSettings.wallpaperOpacity.key}.$roomId';
String _blurKey(String roomId) => '${AppSettings.wallpaperBlur.key}.$roomId';
String _sourceKey(String roomId) => '${AppSettings.wallpaperPath.key}.$roomId';

String? _roomSource(String roomId) {
  final value = AppSettings.store.getString(_sourceKey(roomId));
  return value == null || value.isEmpty ? null : value;
}

/// Whether [roomId] overrides the global wallpaper with its own setting.
bool hasRoomWallpaper(String roomId) => _roomSource(roomId) != null;

/// The wallpaper of a chat, with everything needed to render it.
class WallpaperConfig {
  /// Identifies the stored bytes on web. Empty for the global wallpaper.
  final String storageKey;

  /// A file path (native platforms), [wallpaperIndexedDbMarker] (web),
  /// [wallpaperNone], or `null` when nothing is configured.
  final String? source;

  final double opacity;
  final double blur;

  /// Whether this comes from the room itself rather than from the global
  /// settings.
  final bool isRoomSpecific;

  const WallpaperConfig({
    required this.storageKey,
    required this.source,
    required this.opacity,
    required this.blur,
    required this.isRoomSpecific,
  });

  ImageProvider? get image => _imageProviderFor(storageKey, source);

  bool get hasImage => image != null;
}

/// The global wallpaper configuration.
WallpaperConfig get globalWallpaper => WallpaperConfig(
  storageKey: '',
  source: AppSettings.wallpaperPath.value.isEmpty
      ? null
      : AppSettings.wallpaperPath.value,
  opacity: AppSettings.wallpaperOpacity.value,
  blur: AppSettings.wallpaperBlur.value,
  isRoomSpecific: false,
);

/// The wallpaper to render in [roomId], falling back to the global one when
/// the room has no wallpaper of its own.
WallpaperConfig wallpaperConfigFor(String? roomId) {
  if (roomId == null) return globalWallpaper;

  final source = _roomSource(roomId);
  if (source == null) return globalWallpaper;

  final store = AppSettings.store;
  return WallpaperConfig(
    storageKey: roomId,
    source: source,
    opacity: store.getDouble(_opacityKey(roomId)) ?? _defaultOpacity,
    blur: store.getDouble(_blurKey(roomId)) ?? _defaultBlur,
    isRoomSpecific: true,
  );
}

/// Loads the global wallpaper into memory. Call once during startup.
///
/// Room wallpapers are loaded on demand instead, see [_bytesFor], so that a
/// user with a wallpaper in many chats does not pay for all of them at every
/// start.
///
/// Also migrates wallpapers of older versions, which were stored inline in the
/// settings as a base64 data URL, into IndexedDB.
Future<void> initWallpaper() async {
  if (!kIsWeb) return;

  final source = AppSettings.wallpaperPath.value;
  if (source.isEmpty || source == wallpaperNone) return;

  try {
    if (source.startsWith('data:')) {
      final bytes = _decodeDataUrl(source);
      if (bytes == null) {
        await AppSettings.wallpaperPath.setItem('');
        return;
      }
      await saveWallpaperBytes('', bytes);
      await AppSettings.wallpaperPath.setItem(wallpaperIndexedDbMarker);
      _wallpaperBytes[''] = bytes;
      return;
    }

    final bytes = await loadWallpaperBytes('');
    if (bytes == null) {
      // The setting points at something we cannot restore, e.g. a file path
      // from a native installation of a synced account.
      await AppSettings.wallpaperPath.setItem('');
      return;
    }
    _wallpaperBytes[''] = bytes;
  } catch (e, s) {
    Logs().w('Unable to load the global chat wallpaper', e, s);
  } finally {
    _resolved.add('');
  }
}

/// Storage keys whose bytes were looked up already, so that a wallpaper which
/// is not in IndexedDB is not requested over and over from `build`.
final Set<String> _resolved = {};
final Set<String> _loading = {};

/// The bytes of a wallpaper, kicking off a load the first time they are asked
/// for.
///
/// Returns `null` while the load is still running; [wallpaperRevision] fires
/// once it finished, which repaints the chats.
Uint8List? _bytesFor(String storageKey, String source) {
  final cached = _wallpaperBytes[storageKey];
  if (cached != null) return cached;
  if (_resolved.contains(storageKey) || _loading.contains(storageKey)) {
    return null;
  }

  _loading.add(storageKey);
  unawaited(_load(storageKey, source));
  return null;
}

Future<void> _load(String storageKey, String source) async {
  try {
    final bytes = await loadWallpaperBytes(storageKey);
    if (bytes != null) {
      _wallpaperBytes[storageKey] = bytes;
    } else if (storageKey.isNotEmpty) {
      // Nothing stored under this key, so the setting points at something we
      // cannot restore. Drop it rather than claiming the room has a wallpaper.
      await AppSettings.store.remove(_sourceKey(storageKey));
    }
  } catch (e, s) {
    Logs().w('Unable to load the chat wallpaper of "$storageKey"', e, s);
  } finally {
    _loading.remove(storageKey);
    _resolved.add(storageKey);
    _notifyWallpaperChanged();
  }
}

/// Stores [bytes] as the wallpaper of [roomId], or as the global one when
/// [roomId] is `null`.
Future<void> saveWallpaper({
  required String? roomId,
  required Uint8List bytes,
}) async {
  final storageKey = roomId ?? '';
  final String source;

  if (kIsWeb) {
    // Web has no writable file system, so the image goes into IndexedDB and
    // the setting only remembers that there is one.
    await saveWallpaperBytes(storageKey, bytes);
    _wallpaperBytes[storageKey] = bytes;
    _resolved.add(storageKey);
    source = wallpaperIndexedDbMarker;
  } else {
    final directory = (await getApplicationDocumentsDirectory()).path;
    final name =
        'wallpaper_${storageKey.hashCode}_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('$directory/$name');
    await file.writeAsBytes(bytes);

    // Drop the file the setting pointed at before, so that repeatedly picking
    // a wallpaper does not pile up images.
    await _deleteFileOf(roomId);
    source = file.path;
  }

  await _setSource(roomId, source);
  _notifyWallpaperChanged();
}

/// Removes the wallpaper of [roomId], or the global one when [roomId] is
/// `null`.
///
/// A room falls back to the global wallpaper afterwards; use
/// [setRoomWallpaperToNone] to show no wallpaper instead.
Future<void> deleteWallpaper({required String? roomId}) async {
  final storageKey = roomId ?? '';

  _wallpaperBytes.remove(storageKey);
  _resolved.remove(storageKey);
  if (kIsWeb) {
    try {
      await deleteWallpaperBytes(storageKey);
    } catch (e, s) {
      Logs().w('Unable to delete the chat wallpaper', e, s);
    }
  } else {
    await _deleteFileOf(roomId);
  }

  if (roomId == null) {
    await AppSettings.wallpaperPath.setItem('');
    await AppSettings.wallpaperOpacity.setItem(_defaultOpacity);
    await AppSettings.wallpaperBlur.setItem(_defaultBlur);
    _notifyWallpaperChanged();
    return;
  }
  await AppSettings.store.remove(_sourceKey(roomId));
  await AppSettings.store.remove(_opacityKey(roomId));
  await AppSettings.store.remove(_blurKey(roomId));
  _notifyWallpaperChanged();
}

/// Makes [roomId] show no wallpaper at all, even when a global one is set.
Future<void> setRoomWallpaperToNone(String roomId) async {
  _wallpaperBytes.remove(roomId);
  _resolved.remove(roomId);
  if (kIsWeb) {
    try {
      await deleteWallpaperBytes(roomId);
    } catch (_) {}
  } else {
    await _deleteFileOf(roomId);
  }
  await _setSource(roomId, wallpaperNone);
  _notifyWallpaperChanged();
}

Future<void> setWallpaperOpacity({
  required String? roomId,
  required double opacity,
}) async {
  await (roomId == null
      ? AppSettings.wallpaperOpacity.setItem(opacity)
      : AppSettings.store.setDouble(_opacityKey(roomId), opacity));
  _notifyWallpaperChanged();
}

Future<void> setWallpaperBlur({
  required String? roomId,
  required double blur,
}) async {
  await (roomId == null
      ? AppSettings.wallpaperBlur.setItem(blur)
      : AppSettings.store.setDouble(_blurKey(roomId), blur));
  _notifyWallpaperChanged();
}

Future<void> _setSource(String? roomId, String source) => roomId == null
    ? AppSettings.wallpaperPath.setItem(source)
    : AppSettings.store.setString(_sourceKey(roomId), source);

Future<void> _deleteFileOf(String? roomId) async {
  if (kIsWeb) return;
  final previous = roomId == null
      ? (AppSettings.wallpaperPath.value.isEmpty
            ? null
            : AppSettings.wallpaperPath.value)
      : _roomSource(roomId);
  if (previous == null ||
      previous == wallpaperNone ||
      previous == wallpaperIndexedDbMarker ||
      previous.startsWith('data:')) {
    return;
  }
  try {
    final file = File(previous);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

Uint8List? _decodeDataUrl(String value) {
  final separator = value.indexOf(',');
  if (separator == -1) return null;
  try {
    return base64Decode(value.substring(separator + 1));
  } catch (_) {
    return null;
  }
}

ImageProvider? _imageProviderFor(String storageKey, String? source) {
  if (source == null || source.isEmpty || source == wallpaperNone) return null;

  if (kIsWeb) {
    // Not migrated yet, e.g. when `initWallpaper` has not run.
    if (source.startsWith('data:')) {
      final decoded = _decodeDataUrl(source);
      if (decoded != null) return MemoryImage(decoded);
      return null;
    }
    final bytes = _bytesFor(storageKey, source);
    return bytes == null ? null : MemoryImage(bytes);
  }

  // A marker or data URL is meaningless on native platforms.
  if (source.startsWith('data:') || source == wallpaperIndexedDbMarker) {
    return null;
  }
  return FileImage(File(source));
}

/// Drops every stored wallpaper of a room the user is no longer in.
///
/// Leaving a chat from this device cleans up right away, but a chat can also
/// be left from another client, so the leftovers are swept on every start.
Future<void> pruneWallpapersOfLeftRooms(List<Client> clients) async {
  final prefix = '${AppSettings.wallpaperPath.key}.';
  final storedRoomIds = AppSettings.store
      .getKeys()
      .where((key) => key.startsWith(prefix))
      .map((key) => key.substring(prefix.length))
      .toSet();
  if (storedRoomIds.isEmpty) return;

  final loggedIn = clients.where((client) => client.isLogged()).toList();
  // Without a logged in client every room would look gone, which would wipe
  // the settings of somebody who is merely signed out.
  if (loggedIn.isEmpty) return;

  for (final client in loggedIn) {
    await client.roomsLoading;
  }
  final knownRoomIds = {
    for (final client in loggedIn)
      for (final room in client.rooms) room.id,
  };

  for (final roomId in storedRoomIds) {
    if (knownRoomIds.contains(roomId)) continue;
    Logs().v('Removing the wallpaper of the left room $roomId');
    await deleteWallpaper(roomId: roomId);
  }
}

/// Shrinks and re-encodes a picked image so that a wallpaper never costs more
/// than it has to, neither on disk nor in IndexedDB.
Future<Uint8List> compressWallpaperBytes(Uint8List rawBytes) async {
  try {
    await native.init();

    final codec = await instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final rgbaData = await frame.image.toByteData();
    if (rgbaData == null) return rawBytes;

    final rgba = Uint8List.view(
      rgbaData.buffer,
      rgbaData.offsetInBytes,
      rgbaData.lengthInBytes,
    );

    final width = frame.image.width;
    final height = frame.image.height;

    frame.image.dispose();
    codec.dispose();

    var nativeImg = native.Image.fromRGBA(width, height, rgba);

    // Scale down if either dimension exceeds the limit.
    if (width > wallpaperMaxDimension || height > wallpaperMaxDimension) {
      final fit = applyBoxFit(
        BoxFit.scaleDown,
        Size(width.toDouble(), height.toDouble()),
        Size(
          wallpaperMaxDimension.toDouble(),
          wallpaperMaxDimension.toDouble(),
        ),
      ).destination;

      final scaled = nativeImg.resample(
        fit.width.round(),
        fit.height.round(),
        native.Transform.lanczos,
      );
      nativeImg.free();
      nativeImg = scaled;
    }

    final compressed = await nativeImg.toJpeg(wallpaperJpegQuality);
    nativeImg.free();
    return compressed;
  } catch (e, s) {
    Logs().e('Failed to compress wallpaper image', e, s);
    return rawBytes;
  }
}
