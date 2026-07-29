import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:extera_next/pages/image_viewer/image_viewer.dart';
import 'package:extera_next/utils/localized_exception_extension.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/blur_hash.dart';
import '../../../utils/error_reporter.dart';
import '../../widgets/mxc_image.dart';

class EventVideoPlayer extends StatefulWidget {
  final Event event;
  final ImageViewerController ivController;

  const EventVideoPlayer(this.event, this.ivController, {super.key});

  @override
  EventVideoPlayerState createState() => EventVideoPlayerState();
}

class EventVideoPlayerState extends State<EventVideoPlayer> {
  Player? _mediaKitPlayer;
  VideoController? _mediaKitController;

  double? _downloadProgress;

  void _downloadAction() async {
    try {
      _disposeControllers();
      final player = Player();
      _mediaKitPlayer = player;
      _mediaKitController = VideoController(player);

      if (widget.event.room.encrypted) {
        final fileSize = widget.event.content
            .tryGetMap<String, dynamic>('info')
            ?.tryGet<int>('size');

        final videoFile = await widget.event.downloadAndDecryptAttachment(
          onDownloadProgress: fileSize == null
              ? null
              : (progress) {
                  final progressPercentage = progress / fileSize;
                  setState(() {
                    _downloadProgress = progressPercentage < 1
                        ? progressPercentage
                        : null;
                  });
                },
        );

        final tempDir = await getTemporaryDirectory();
        final fileName = Uri.encodeComponent(
          widget.event.attachmentOrThumbnailMxcUrl()!.pathSegments.last,
        );
        final file = File('${tempDir.path}/${fileName}_${videoFile.name}');
        if (!await file.exists()) {
          await file.writeAsBytes(videoFile.bytes);
        }
        await player.open(Media(file.path));
      } else {
        final videoUrl = await widget.event.attachmentMxcUrl!.getDownloadUri(
          widget.event.room.client,
        );
        Logs().d("Video url: $videoUrl");
        await player.open(
          Media(
            videoUrl.toString(),
            httpHeaders: {
              'authorization': 'Bearer ${widget.event.room.client.accessToken}',
            },
          ),
        );
      }

      if (widget.ivController.currentEvent.eventId != widget.event.eventId) {
        dispose();
        return;
      }

      setState(() {});
    } on IOException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      }
    } catch (e, s) {
      if (mounted) {
        ErrorReporter(context, 'Unable to play video').onErrorCallback(e, s);
      }
    }
  }

  void _disposeControllers() {
    _mediaKitPlayer?.dispose();
    _mediaKitPlayer = null;
    _mediaKitController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
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

    final videoHeight =
        event.content.tryGetMap<String, dynamic>('info')?.tryGet<int>('h') ??
            1;
    final videoWidth =
        event.content.tryGetMap<String, dynamic>('info')?.tryGet<int>('w') ??
            1;
    final blurHash =
        event.content.tryGetMap<String, dynamic>('info')?.tryGet<String>('xyz.amorgan.blurhash');
    final hasThumbnail = event.hasThumbnail;

    // Calculate the maximum dimensions that the video can have.
    final height = MediaQuery.of(context).size.height - 52;
    final width = videoWidth * (height / videoHeight);

    final mediaKitController = _mediaKitController;

    if (mediaKitController != null) {
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Video(
            controller: mediaKitController,
            controls: MaterialVideoControls,
          ),
        ),
      );
    }

    return Stack(
      children: [
        Center(
          child: Hero(
            tag: widget.event.eventId,
            child: hasThumbnail
                ? MxcImage(
                    event: widget.event,
                    isThumbnail: true,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    placeholder: (context) => BlurHash(
                      blurhash: blurHash,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                    ),
                  )
                : BlurHash(
                    blurhash: blurHash,
                    width: width,
                    height: height,
                  ),
          ),
        ),
        Center(
          child: CircularProgressIndicator.adaptive(
            value: _downloadProgress,
          ),
        ),
      ],
    );
  }
}
