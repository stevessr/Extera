import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/file_send_relation.dart';
import 'package:extera_next/utils/clean_exif.dart';
import 'package:extera_next/utils/content_warning.dart';
import 'package:extera_next/utils/foreground_task_manager.dart';
import 'package:extera_next/utils/loading_snackbar_extension.dart';
import 'package:extera_next/utils/localized_exception_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/size_string.dart';
import 'package:extera_next/utils/svg_image.dart';
import 'package:extera_next/widgets/adaptive_dialogs/dialog_text_field.dart';
import 'package:extera_next/widgets/adaptive_dialogs/image_editor_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';

import '../../utils/resize_video.dart';

class SendFileDialog extends StatefulWidget {
  final Room room;
  final Thread? thread;
  final List<XFile> files;
  final BuildContext outerContext;
  final Event? replyEvent;
  final void Function()? onClearReply;

  const SendFileDialog({
    required this.room,
    required this.thread,
    required this.files,
    required this.outerContext,
    this.onClearReply,
    this.replyEvent,
    super.key,
  });

  @override
  SendFileDialogState createState() => SendFileDialogState();
}

class SendFileDialogState extends State<SendFileDialog> {
  bool compress = true;
  bool isSending = false;
  String? contentWarning;

  final Map<String, Future<MatrixImageFile?>> _videoPreviewFutures = {};

  /// Images smaller than 20kb don't need compression.
  static const int minSizeToCompress = 20 * 1000;

  final TextEditingController _labelTextController = TextEditingController();

  Future<void> _send() async {
    if (isSending) return;
    final scaffoldMessenger = ScaffoldMessenger.of(widget.outerContext);
    final l10n = L10n.of(context);
    final convertLinebreaks = Matrix.of(
      context,
    ).client.convertLinebreaksInFormatting;
    final label = _labelTextController.text.trim();
    final warning = contentWarning;
    final replyEventId = widget.replyEvent?.eventId;
    final threadRootEventId = widget.thread?.rootEvent.eventId;
    final lastThreadEvent = widget.thread?.lastEvent;
    final threadLastEventId =
        lastThreadEvent != null && lastThreadEvent.status.isSynced
        ? lastThreadEvent.eventId
        : threadRootEventId;
    final files = List<XFile>.of(widget.files);
    var foregroundUploadAcquired = false;

    try {
      setState(() {
        isSending = true;
      });
      final clientConfig = await widget.room.client.getConfig();
      final maxUploadSize = clientConfig.mUploadSize ?? 100 * 1000 * 1000;

      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
      }

      if (widget.outerContext.mounted) {
        foregroundUploadAcquired = await ForegroundTaskManager.startFileUpload(
          widget.outerContext,
        );
      }

      for (final xfile in files) {
        MatrixFile file;
        MatrixImageFile? thumbnail;
        final length = await xfile.length();
        final mimeType = xfile.mimeType ?? lookupMimeType(xfile.path);
        final name = xfile.name.isNotEmpty
            ? xfile.name
            : mimeType == null
            ? 'file'
            : "file.${mimeType.split('/').last.split(';').first}";
        // SVG is an XML vector image: EXIF cleanup and bitmap resizing must
        // not rewrite it. Some file pickers report .svg as octet-stream.
        final isSvg =
            mimeType?.split(';').first.trim().toLowerCase() ==
                'image/svg+xml' ||
            name.toLowerCase().endsWith('.svg');
        final effectiveMimeType = isSvg ? 'image/svg+xml' : mimeType;
        final canShrinkImage =
            !isSvg && effectiveMimeType?.startsWith('image') == true;
        final canCompressVideo =
            PlatformInfos.isMobile &&
            effectiveMimeType?.startsWith('video') == true &&
            length > minSizeToCompress &&
            compress;

        if (length > maxUploadSize &&
            !(compress && canShrinkImage) &&
            !canCompressVideo) {
          throw FileTooBigMatrixException(length, maxUploadSize);
        }

        // If file is a video, shrink it!
        if (PlatformInfos.isMobile &&
            mimeType != null &&
            mimeType.startsWith('video') &&
            length > minSizeToCompress &&
            compress) {
          scaffoldMessenger.showLoadingSnackBar(l10n.compressVideo);
          file = await xfile.resizeVideo();
        } else if (mimeType != null &&
            mimeType.startsWith('image') &&
            AppSettings.cleanExif.value &&
            !isSvg) {
          // Else we just create a MatrixFile
          file = MatrixFile(
            bytes: Uint8List.fromList(
              ExifCleaner.removeExifData(await xfile.readAsBytes()),
            ),
            name: name,
            mimeType: effectiveMimeType,
          ).detectFileType;
        } else {
          // Else we just create a MatrixFile
          file = MatrixFile(
            bytes: await xfile.readAsBytes(),
            name: name,
            mimeType: effectiveMimeType,
          ).detectFileType;
        }

        // Shrink images before sending, but keep the original if the
        // shrunk result would be bigger than the source file.
        if (compress && canShrinkImage && file is MatrixImageFile) {
          file = await file.shrinkWithSizeCheck(
            maxDimension: 1600,
            client: widget.room.client,
          );
        }

        if (file.bytes.length > maxUploadSize) {
          throw FileTooBigMatrixException(file.bytes.length, maxUploadSize);
        }

        if (PlatformInfos.isMobile &&
            mimeType != null &&
            mimeType.startsWith('video')) {
          try {
            scaffoldMessenger.showLoadingSnackBar(
              l10n.generatingVideoThumbnail,
            );
            thumbnail = await _getVideoPreview(xfile);
          } catch (e) {
            Logs().e("Failed to generate video thumbnail", e);
            if (widget.outerContext.mounted && scaffoldMessenger.mounted) {
              scaffoldMessenger.showLoadingSnackBar(
                e.toLocalizedString(widget.outerContext),
              );
            }
          }
        }

        if (files.length > 1) {
          scaffoldMessenger.showLoadingSnackBar(
            l10n.sendingAttachmentCountOfCount(
              files.indexOf(xfile) + 1,
              files.length,
            ),
          );
        } else {
          scaffoldMessenger.clearSnackBars();
        }

        final extraContent = <String, dynamic>{};

        applyContentWarning(extraContent, warning);

        if (label.isNotEmpty) {
          extraContent['body'] = label;
          final html = markdown(
            label,
            getEmotePacks: () =>
                widget.room.getImagePacksFlat(ImagePackUsage.emoticon),
            getMention: widget.room.getMention,
            convertLinebreaks: convertLinebreaks,
          );

          // if the decoded html is the same as the body, there is no need in sending a formatted message
          if (HtmlUnescape().convert(
                html.replaceAll(RegExp(r'<br />\n?'), '\n'),
              ) !=
              label) {
            extraContent['format'] = 'org.matrix.custom.html';
            extraContent['formatted_body'] = html;
          }
        }

        final relation = buildFileSendRelation(
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadLastEventId,
          inReplyToEventId: replyEventId,
        );
        if (relation != null) extraContent['m.relates_to'] = relation;

        final transactionId = widget.room.client.generateUniqueTransactionId();
        try {
          await widget.room.sendFileEvent(
            file,
            txid: transactionId,
            thumbnail: thumbnail,
            extraContent: extraContent,
            threadLastEventId: threadLastEventId,
            threadRootEventId: threadRootEventId,
          );
        } on MatrixException catch (e) {
          final retryAfterMs = e.retryAfterMs;
          if (e.error != MatrixError.M_LIMIT_EXCEEDED || retryAfterMs == null) {
            rethrow;
          }
          final retryAfterDuration = Duration(
            milliseconds: retryAfterMs + 1000,
          );

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                l10n.serverLimitReached(retryAfterDuration.inSeconds),
              ),
            ),
          );
          await Future.delayed(retryAfterDuration);

          scaffoldMessenger.showLoadingSnackBar(l10n.sendingAttachment);

          await widget.room.sendFileEvent(
            file,
            txid: transactionId,
            thumbnail: thumbnail,
            extraContent: extraContent,
            threadLastEventId: threadLastEventId,
            threadRootEventId: threadRootEventId,
          );
        }
        widget.onClearReply?.call();
      }
      scaffoldMessenger.clearSnackBars();
    } catch (e) {
      Logs().e('error on send', e);
      if (mounted) {
        setState(() {
          isSending = false;
        });
      }
      scaffoldMessenger.clearSnackBars();
      if (widget.outerContext.mounted && scaffoldMessenger.mounted) {
        final theme = Theme.of(widget.outerContext);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            backgroundColor: theme.colorScheme.errorContainer,
            closeIconColor: theme.colorScheme.onErrorContainer,
            content: Text(
              e.toLocalizedString(widget.outerContext),
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            duration: const Duration(seconds: 30),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (foregroundUploadAcquired) {
        await ForegroundTaskManager.stopTask(taskType: .fileUpload);
      }
    }
  }

  Future<String> _calcCombinedFileSize() async {
    final lengths = await Future.wait(
      widget.files.map((file) => file.length()),
    );
    return lengths.fold<double>(0, (p, length) => p + length).sizeString;
  }

  Future<MatrixImageFile?> _getVideoPreview(XFile file) {
    final key = '${file.path}\u0000${file.name}';
    return _videoPreviewFutures.putIfAbsent(key, file.getVideoThumbnail);
  }

  Widget _buildVideoPreview(int index) {
    final file = widget.files[index];
    final width = widget.files.length == 1 ? 220.0 : 256.0;

    return Material(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
      color: Colors.transparent,
      clipBehavior: Clip.hardEdge,
      child: FutureBuilder<MatrixImageFile?>(
        future: _getVideoPreview(file),
        builder: (context, snapshot) {
          final thumbnail = snapshot.data;
          final preview = snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator.adaptive())
              : thumbnail == null
              ? const Center(child: Icon(Icons.video_file_outlined, size: 64))
              : Image.memory(
                  thumbnail.bytes,
                  height: 256,
                  width: width,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    Logs().w('Unable to preview video', error, stackTrace);
                    return const Center(
                      child: Icon(Icons.video_file_outlined, size: 64),
                    );
                  },
                );

          return SizedBox(
            width: width,
            height: 256,
            child: Stack(
              alignment: Alignment.center,
              children: [
                preview,
                if (thumbnail != null)
                  const Icon(
                    Icons.play_circle_outline,
                    size: 56,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 8)],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void editImage(int index) async {
    final file = widget.files[index];
    final edited = await showImageEditor(
      context: context,
      byteArray: await file.readAsBytes(),
    );
    if (edited == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.of(context).imageEditFailed)));
      return;
    }
    setState(() {
      widget.files[index] = XFile.fromData(
        edited,
        mimeType: file.mimeType,
        name: file.name,
        path: file.path,
      );
    });
  }

  @override
  void dispose() {
    _labelTextController.dispose();
    super.dispose();
  }

  Widget _imagePreviewError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    Logs().w('Unable to preview image', error, stackTrace);
    return const Center(
      child: SizedBox(
        width: 256,
        height: 256,
        child: Icon(Icons.broken_image_outlined, size: 64),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    var sendStr = L10n.of(context).sendFile;
    final uniqueFileType = widget.files
        .map(
          (file) => file.name.toLowerCase().endsWith('.svg')
              ? 'image/svg+xml'
              : file.mimeType ?? lookupMimeType(file.name),
        )
        .map((mimeType) => mimeType?.split('/').first)
        .toSet()
        .singleOrNull;

    final fileName = widget.files.length == 1
        ? widget.files.single.name
        : L10n.of(context).countFiles(widget.files.length);
    final fileTypes = widget.files
        .map((file) => file.name.split('.').last)
        .toSet()
        .join(', ')
        .toUpperCase();

    if (uniqueFileType == 'image') {
      if (widget.files.length == 1) {
        sendStr = L10n.of(context).sendImage;
      } else {
        sendStr = L10n.of(context).sendImages(widget.files.length);
      }
    } else if (uniqueFileType == 'audio') {
      sendStr = L10n.of(context).sendAudio;
    } else if (uniqueFileType == 'video') {
      sendStr = L10n.of(context).sendVideo;
    }

    final compressionSupported =
        uniqueFileType != 'video' || PlatformInfos.isMobile;

    return FutureBuilder<String>(
      future: _calcCombinedFileSize(),
      builder: (context, snapshot) {
        final sizeString =
            snapshot.data ?? L10n.of(context).calculatingFileSize;

        return AlertDialog.adaptive(
          title: Text(sendStr),
          content: SizedBox(
            width: 256,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  if (uniqueFileType == 'image')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: SizedBox(
                        height: 256,
                        child: Center(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: widget.files.length,
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Material(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius / 2,
                                ),
                                color: Colors.transparent,
                                clipBehavior: Clip.hardEdge,
                                child: FutureBuilder(
                                  future: widget.files[i].readAsBytes(),
                                  builder: (context, snapshot) {
                                    final bytes = snapshot.data;
                                    if (bytes == null) {
                                      return const Center(
                                        child:
                                            CircularProgressIndicator.adaptive(),
                                      );
                                    }
                                    if (snapshot.error != null) {
                                      Logs().w(
                                        'Unable to preview image',
                                        snapshot.error,
                                        snapshot.stackTrace,
                                      );
                                      return const Center(
                                        child: SizedBox(
                                          width: 256,
                                          height: 256,
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            size: 64,
                                          ),
                                        ),
                                      );
                                    }
                                    return Stack(
                                      children: [
                                        isSvgImage(bytes)
                                            ? SvgPicture.memory(
                                                bytes,
                                                height: 256,
                                                width: widget.files.length == 1
                                                    ? 256 - 36
                                                    : null,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    _imagePreviewError,
                                              )
                                            : Image.memory(
                                                bytes,
                                                height: 256,
                                                width: widget.files.length == 1
                                                    ? 256 - 36
                                                    : null,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    _imagePreviewError,
                                              ),
                                        if (!isSvgImage(bytes))
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: IconButton.filledTonal(
                                              onPressed: () => editImage(i),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (uniqueFileType == 'video')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: SizedBox(
                        height: 256,
                        child: Center(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: widget.files.length,
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: _buildVideoPreview(i),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (uniqueFileType != 'image')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        children: [
                          Icon(
                            uniqueFileType == null
                                ? Icons.description_outlined
                                : uniqueFileType == 'video'
                                ? Icons.video_file_outlined
                                : uniqueFileType == 'audio'
                                ? Icons.audio_file_outlined
                                : Icons.description_outlined,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$sizeString - $fileTypes',
                                  style: theme.textTheme.labelSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.files.length == 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: DialogTextField(
                        controller: _labelTextController,
                        labelText: L10n.of(context).optionalMessage,
                        keyboardType: .multiline,
                        maxLength: 4096,
                        counterText: '',
                        textInputAction: AppSettings.sendOnEnter.value
                            ? .send
                            : null,
                        onSubmitted: (_) => _send(),
                        suffix: PopupMenuButton<String?>(
                          initialValue: contentWarning,
                          onSelected: (value) {
                            setState(() {
                              contentWarning = value;
                            });
                          },
                          icon: Icon(
                            contentWarning == null
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: L10n.of(context).contentWarning,
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: null,
                              child: Text(L10n.of(context).none),
                            ),
                            for (final type in ContentWarningType.values)
                              PopupMenuItem(
                                value: type.value,
                                child: Text(type.label(L10n.of(context))),
                              ),
                          ],
                        ),
                      ),
                    ),
                  // Workaround for SwitchListTile.adaptive crashes in CupertinoDialog
                  if ({'image', 'video'}.contains(uniqueFileType))
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Switch.adaptive(
                          value: compressionSupported && compress,
                          onChanged: compressionSupported
                              ? (v) => setState(() => compress = v)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    L10n.of(context).compress,
                                    style: theme.textTheme.titleMedium,
                                    textAlign: TextAlign.left,
                                  ),
                                ],
                              ),
                              if (!compress)
                                Text(
                                  ' ($sizeString)',
                                  style: theme.textTheme.labelSmall,
                                ),
                              if (!compressionSupported)
                                Text(
                                  L10n.of(context).notSupportedOnThisDevice,
                                  style: theme.textTheme.labelSmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            if (!isSending)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                ),
                onPressed: () =>
                    Navigator.of(context, rootNavigator: false).pop(),
                child: Text(L10n.of(context).cancel),
              ),
            if (!isSending)
              FilledButton(
                onPressed: _send,
                child: Text(L10n.of(context).send),
              ),
            if (isSending) const CircularProgressIndicator.adaptive(),
          ],
        );
      },
    );
  }
}
