import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:chewie/chewie.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:video_player/video_player.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/image_viewer/image_viewer.dart';
import 'package:extera_next/utils/localized_exception_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/blur_hash.dart';

import '../../../utils/error_reporter.dart';
import '../../widgets/mxc_image.dart';

/// Persistent on-disk cache for downloaded video attachments.
///
/// Downloads are shared between playback sessions and survive restarts, so a
/// video opened twice (or once per viewer recreation) is fetched from the
/// homeserver only once.
final _videoPlaybackCache = _VideoPlaybackCache();

class _VideoPlaybackCache {
  static const _cacheDirectoryName = 'video_cache';
  static const _filePrefix = 'extera_video_';
  static const _maxCacheAge = Duration(days: 30);
  static const _maxCacheBytes = 512 * 1024 * 1024;

  final Map<String, int> _activeReferences = {};
  Future<Directory>? _directoryFuture;
  Future<void>? _cleanupFuture;

  Future<Directory> get _directory => _directoryFuture ??= _createDirectory();

  Future<Directory> _createDirectory() async {
    // Application support survives image-viewer/player disposal and process
    // restarts. It is deliberately not the OS temporary directory: a video
    // should remain reusable until the cache policy removes it.
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      '${supportDirectory.path}/$_cacheDirectoryName',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File?> acquire(Event event) async {
    try {
      final file = await _fileFor(event);
      if (!await file.exists() || await file.length() <= 0) return null;

      // Touch on reuse so actively revisited media is not considered stale.
      try {
        await file.setLastModified(DateTime.now());
      } on FileSystemException {
        // A timestamp update is an optimization, not a reason to fail
        // playback when the underlying storage has unusual restrictions.
      }
      _retain(file.path);
      return file;
    } on FileSystemException catch (e, s) {
      Logs().w('Unable to read cached video file', e, s);
      return null;
    }
  }

  Future<File> store(Event event, List<int> bytes) async {
    final file = await _fileFor(event);
    final stagingFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );

    try {
      // Write beside the final file and rename only after the complete bytes
      // have been flushed. A process kill can therefore leave a .part file,
      // but never a partial file that looks playable to the next launch.
      await stagingFile.writeAsBytes(bytes, flush: true);
      await stagingFile.rename(file.path);
      _retain(file.path);
      return file;
    } finally {
      try {
        if (await stagingFile.exists()) await stagingFile.delete();
      } on FileSystemException catch (e, s) {
        Logs().w('Unable to remove video cache staging file', e, s);
      }
    }
  }

  Future<void> invalidate(Event event) async {
    try {
      final file = await _fileFor(event);
      if (_activeReferences.containsKey(file.path)) return;
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e, s) {
      Logs().w('Unable to invalidate cached video file', e, s);
    }
  }

  void release(String path) {
    final references = _activeReferences[path];
    if (references == null || references <= 1) {
      _activeReferences.remove(path);
    } else {
      _activeReferences[path] = references - 1;
    }
  }

  void scheduleCleanup() {
    if (_cleanupFuture != null) return;
    final future = _cleanup();
    _cleanupFuture = future;
    unawaited(future);
  }

  Future<void> _cleanup() async {
    try {
      final directory = await _directory;
      if (!await directory.exists()) return;

      final now = DateTime.now();
      final entries = <_VideoCacheEntry>[];
      var totalBytes = 0;

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = entity.path.split(Platform.pathSeparator).last;
        if (!fileName.startsWith(_filePrefix)) continue;

        final stat = await entity.stat();
        if (fileName.endsWith('.part')) {
          if (now.isAfter(stat.modified.add(const Duration(days: 1)))) {
            await _delete(entity);
          }
          continue;
        }

        final entry = _VideoCacheEntry(entity, stat.size, stat.modified);
        entries.add(entry);
        totalBytes += entry.size;
      }

      for (final entry in entries) {
        if (!now.isAfter(entry.modified.add(_maxCacheAge))) continue;
        if (await _delete(entry.file)) totalBytes -= entry.size;
      }

      if (totalBytes > _maxCacheBytes) {
        entries.sort((a, b) => a.modified.compareTo(b.modified));
        for (final entry in entries) {
          if (totalBytes <= _maxCacheBytes) break;
          if (await _delete(entry.file)) totalBytes -= entry.size;
        }
      }
    } catch (e, s) {
      Logs().w('Unable to clean video cache', e, s);
    } finally {
      _cleanupFuture = null;
    }
  }

  Future<File> _fileFor(Event event) async {
    final attachmentPath = event.attachmentMxcUrl?.pathSegments;
    final attachmentName = attachmentPath == null || attachmentPath.isEmpty
        ? event.body
        : attachmentPath.last;
    final sourceName = event.content.tryGet<String>('filename') ?? event.body;
    final extension = _videoFileExtension(sourceName, event.attachmentMimetype);
    final fileName =
        '$_filePrefix${_safeVideoFilePart(event.room.id)}_${_safeVideoFilePart(event.eventId)}_${_safeVideoFilePart(attachmentName)}.$extension';
    final directory = await _directory;
    return File('${directory.path}/$fileName');
  }

  Future<bool> _delete(File file) async {
    if (_activeReferences.containsKey(file.path)) return false;
    try {
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } on FileSystemException catch (e, s) {
      Logs().w('Unable to remove video cache file', e, s);
      return false;
    }
  }

  void _retain(String path) {
    _activeReferences[path] = (_activeReferences[path] ?? 0) + 1;
  }
}

class _VideoCacheEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _VideoCacheEntry(this.file, this.size, this.modified);
}

String _safeVideoFilePart(String value) {
  final result = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return result.isEmpty ? 'video' : result;
}

String _videoFileExtension(String fileName, String mimeType) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
    return _safeVideoFilePart(fileName.substring(dotIndex + 1)).toLowerCase();
  }

  final mimeExtension = mimeType.split('/').last;
  return mimeExtension.isEmpty
      ? 'video'
      : _safeVideoFilePart(mimeExtension).toLowerCase();
}

class EventVideoPlayer extends StatefulWidget {
  final Event event;
  final ImageViewerController ivController;

  const EventVideoPlayer(this.event, this.ivController, {super.key});

  @override
  EventVideoPlayerState createState() => EventVideoPlayerState();
}

class EventVideoPlayerState extends State<EventVideoPlayer> {
  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;

  double? _downloadProgress;
  String? _playbackError;
  String? _activeVideoPath;
  int _loadGeneration = 0;

  // The video_player package doesn't support Windows and Linux.
  final _supportsVideoPlayer =
      !PlatformInfos.isWindows && !PlatformInfos.isLinux;

  bool _isCurrent(int generation) => mounted && generation == _loadGeneration;

  Future<void> _downloadAction() async {
    if (!_supportsVideoPlayer) {
      widget.event.saveFile(context);
      return;
    }

    final generation = ++_loadGeneration;
    await _disposeControllers();
    if (!_isCurrent(generation)) return;

    setState(() {
      _downloadProgress = null;
      _playbackError = null;
    });

    try {
      final videoPlayerController = await _controllerForPlayback(generation);
      if (!_isCurrent(generation)) {
        // A newer load or disposal owns the state now; this controller was
        // never assigned to the widget so only it is released here.
        unawaited(videoPlayerController.dispose());
        return;
      }

      _videoPlayerController = videoPlayerController;
      await videoPlayerController.initialize();

      if (!_isCurrent(generation) ||
          widget.ivController.currentEvent.eventId != widget.event.eventId) {
        await _disposeControllers();
        return;
      }

      final chewieController = ChewieController(
        videoPlayerController: videoPlayerController,
        useRootNavigator: !kIsWeb,
        autoPlay: true,
        looping: true,
      );

      setState(() {
        _chewieController = chewieController;
        _downloadProgress = null;
      });
    } on IOException catch (e, s) {
      await _handlePlaybackFailure(generation, e, s);
    } catch (e, s) {
      await _handlePlaybackFailure(generation, e, s);
    }
  }

  Future<VideoPlayerController> _controllerForPlayback(int generation) async {
    final event = widget.event;

    // Playing from a local file on Android avoids the platform player having
    // to follow Matrix media redirects, keeps network playback from being cut
    // mid-stream by viewer lifecycle changes, and preserves the authenticated
    // download path for both encrypted and unencrypted rooms. Encrypted rooms
    // always need a local decrypt step anyway.
    final useLocalFile =
        !kIsWeb && (PlatformInfos.isAndroid || event.room.encrypted);
    if (!useLocalFile) {
      if (kIsWeb) {
        final fileSize = event.content
            .tryGetMap<String, dynamic>('info')
            ?.tryGet<int>('size');
        final videoFile = await event.downloadAndDecryptAttachment(
          onDownloadProgress: fileSize == null || fileSize <= 0
              ? null
              : (progress) {
                  if (!_isCurrent(generation)) return;
                  final percentage = (progress / fileSize).clamp(0.0, 1.0);
                  setState(() {
                    _downloadProgress = percentage < 1
                        ? percentage.toDouble()
                        : null;
                  });
                },
        );
        if (!_isCurrent(generation)) {
          throw StateError('Video loading was cancelled');
        }
        final blob = html.Blob([videoFile.bytes]);
        final networkUri = Uri.parse(html.Url.createObjectUrlFromBlob(blob));
        return VideoPlayerController.networkUrl(networkUri);
      }

      final attachment = event.attachmentMxcUrl;
      if (attachment == null) {
        throw StateError('Video event has no attachment URL');
      }
      final videoUrl = await attachment.getDownloadUri(event.room.client);
      Logs().d('Video url: $videoUrl');
      return VideoPlayerController.networkUrl(
        videoUrl,
        httpHeaders: {
          'authorization': 'Bearer ${event.room.client.accessToken}',
        },
      );
    }

    final cachedFile = await _videoPlaybackCache.acquire(event);
    if (!_isCurrent(generation)) {
      if (cachedFile != null) _videoPlaybackCache.release(cachedFile.path);
      throw StateError('Video loading was cancelled');
    }
    if (cachedFile != null) {
      _activeVideoPath = cachedFile.path;
      _videoPlaybackCache.scheduleCleanup();
      return VideoPlayerController.file(cachedFile);
    }

    final fileSize = event.content
        .tryGetMap<String, dynamic>('info')
        ?.tryGet<int>('size');
    final videoFile = await event.downloadAndDecryptAttachment(
      onDownloadProgress: fileSize == null || fileSize <= 0
          ? null
          : (progress) {
              if (!_isCurrent(generation)) return;
              final percentage = (progress / fileSize).clamp(0.0, 1.0);
              setState(() {
                _downloadProgress = percentage < 1
                    ? percentage.toDouble()
                    : null;
              });
            },
    );
    if (!_isCurrent(generation)) {
      throw StateError('Video loading was cancelled');
    }

    final file = await _videoPlaybackCache.store(event, videoFile.bytes);
    if (!_isCurrent(generation)) {
      _videoPlaybackCache.release(file.path);
      throw StateError('Video loading was cancelled');
    }
    _activeVideoPath = file.path;
    _videoPlaybackCache.scheduleCleanup();
    return VideoPlayerController.file(file);
  }

  Future<void> _handlePlaybackFailure(
    int generation,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_isCurrent(generation)) return;

    final message = error is IOException
        ? error.toLocalizedString(context)
        : 'Unable to play video';
    await _disposeControllers();
    if (!kIsWeb && (PlatformInfos.isAndroid || widget.event.room.encrypted)) {
      // An open failure means the cached bytes may be incomplete or
      // unsupported. Keep normal viewer disposal non-destructive, but allow
      // an explicit playback failure to trigger a fresh download on retry.
      await _videoPlaybackCache.invalidate(widget.event);
    }
    if (!_isCurrent(generation)) return;

    setState(() {
      _playbackError = message;
      _downloadProgress = null;
    });

    if (error is IOException) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } else {
      ErrorReporter(
        context,
        'Unable to play video',
      ).onErrorCallback(error, stackTrace);
    }
  }

  Future<void> _disposeControllers() async {
    final chewieController = _chewieController;
    final videoPlayerController = _videoPlayerController;
    final activeVideoPath = _activeVideoPath;

    _chewieController = null;
    _videoPlayerController = null;
    _activeVideoPath = null;

    try {
      chewieController?.dispose();
    } finally {
      try {
        await videoPlayerController?.dispose();
      } finally {
        if (activeVideoPath != null) {
          // The file belongs to the persistent cache, not to this player
          // instance. Release the reference but let cache cleanup decide when
          // it is safe and worthwhile to remove it.
          _videoPlaybackCache.release(activeVideoPath);
        }
      }
    }
  }

  Widget _buildPlaybackError(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.black.withAlpha(210),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 32),
                const SizedBox(height: 8),
                Text(
                  _playbackError ?? 'Unable to play video',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _downloadAction,
                  icon: const Icon(Icons.refresh),
                  label: Text(L10n.of(context).retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Invalidate in-flight loads first so no pending continuation can touch
    // the controllers while they are being disposed below.
    _loadGeneration++;
    unawaited(_disposeControllers());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _downloadAction();
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final infoMap = event.content.tryGetMap<String, Object?>('info');
    final widthValue = infoMap?.tryGet<int>('w');
    final heightValue = infoMap?.tryGet<int>('h');
    final videoWidth = widthValue != null && widthValue > 0
        ? widthValue.toDouble()
        : 400.0;
    final videoHeight = heightValue != null && heightValue > 0
        ? heightValue.toDouble()
        : 300.0;
    final blurHash =
        infoMap?.tryGet<String>('xyz.amorgan.blurhash') ?? fallbackBlurHash;

    // Fit the preview/player into the viewport instead of deriving the width
    // from the height alone: very tall or narrow videos would otherwise
    // overflow the screen.
    final viewport = MediaQuery.sizeOf(context);
    final maxWidth = viewport.width > 0 ? viewport.width : videoWidth;
    final maxHeight = (viewport.height - 52)
        .clamp(1.0, double.infinity)
        .toDouble();
    final videoSize = applyBoxFit(
      BoxFit.contain,
      Size(videoWidth, videoHeight),
      Size(maxWidth, maxHeight),
    ).destination;

    final chewieController = _chewieController;
    if (chewieController != null) {
      return Stack(
        children: [
          Center(
            child: SizedBox(
              width: videoSize.width,
              height: videoSize.height,
              child: Chewie(controller: chewieController),
            ),
          ),
          if (_playbackError != null) _buildPlaybackError(context),
        ],
      );
    }

    return Stack(
      children: [
        Center(
          child: Hero(
            tag: event.eventId,
            child: event.hasThumbnail
                ? MxcImage(
                    event: event,
                    isThumbnail: true,
                    width: videoSize.width,
                    height: videoSize.height,
                    fit: BoxFit.cover,
                    placeholder: (context) => BlurHash(
                      blurhash: blurHash,
                      width: videoSize.width,
                      height: videoSize.height,
                      fit: BoxFit.cover,
                    ),
                  )
                : BlurHash(
                    blurhash: blurHash,
                    width: videoSize.width,
                    height: videoSize.height,
                  ),
          ),
        ),
        if (_playbackError == null)
          Center(
            child: CircularProgressIndicator.adaptive(value: _downloadProgress),
          )
        else
          _buildPlaybackError(context),
      ],
    );
  }
}
