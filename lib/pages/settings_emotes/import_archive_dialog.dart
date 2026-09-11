import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/settings_emotes/settings_emotes.dart';
import 'package:extera_next/utils/client_manager.dart';
import 'package:extera_next/utils/emote_shortcode.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';

class ImportEmoteArchiveDialog extends StatefulWidget {
  final EmotesSettingsController controller;
  final Archive archive;

  const ImportEmoteArchiveDialog({
    super.key,
    required this.controller,
    required this.archive,
  });

  @override
  State<ImportEmoteArchiveDialog> createState() =>
      _ImportEmoteArchiveDialogState();
}

class _ImportEmoteArchiveDialogState extends State<ImportEmoteArchiveDialog> {
  Map<ArchiveFile, String> _importMap = {};

  bool _loading = false;

  double _progress = 0;

  bool get _hasInvalidImportNames {
    final names = _importMap.values.toList(growable: false);
    return names.any((name) => !emoteShortcodePattern.hasMatch(name)) ||
        names.toSet().length != names.length;
  }

  @override
  void initState() {
    _importFileMap();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.of(context).importEmojis),
      content: _loading
          ? Center(child: CircularProgressIndicator(value: _progress))
          : SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: _importMap.entries
                    .map(
                      (e) => _EmojiImportPreview(
                        key: ValueKey(e.key.name),
                        entry: e,
                        onNameChanged: (name) => setState(() {
                          _importMap[e.key] = name;
                        }),
                        onRemove: () =>
                            setState(() => _importMap.remove(e.key)),
                      ),
                    )
                    .toList(),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _loading ? null : Navigator.of(context).pop,
          child: Text(L10n.of(context).cancel),
        ),
        TextButton(
          onPressed: _loading || _importMap.isEmpty || _hasInvalidImportNames
              ? null
              : _addEmotePack,
          child: Text(L10n.of(context).importNow),
        ),
      ],
    );
  }

  void _importFileMap() {
    final usedShortcodes = <String>{};
    _importMap = Map.fromEntries(
      widget.archive.files
          .where((e) => e.isFile)
          .map(
            (e) => MapEntry(
              e,
              uniqueEmoteShortcode(e.name.emoteNameFromPath, usedShortcodes),
            ),
          )
          .sorted((a, b) => a.value.compareTo(b.value)),
    );
  }

  Future<void> _addEmotePack() async {
    setState(() {
      _loading = true;
      _progress = 0;
    });
    final imports = _importMap;
    final successfulUploads = <String>{};

    // check for duplicates first

    final skipKeys = [];

    for (final entry in imports.entries) {
      final imageCode = entry.value;

      if (widget.controller.pack!.images.containsKey(imageCode)) {
        final completer = Completer<OkCancelResult>();
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
          final result = await showOkCancelAlertDialog(
            useRootNavigator: false,
            context: context,
            title: L10n.of(context).emoteExists,
            message: imageCode,
            cancelLabel: L10n.of(context).replace,
            okLabel: L10n.of(context).skip,
          );
          completer.complete(result);
        });

        final result = await completer.future;
        if (result == OkCancelResult.ok) {
          skipKeys.add(entry.key);
        }
      }
    }

    for (final key in skipKeys) {
      imports.remove(key);
    }

    for (final entry in imports.entries) {
      setState(() {
        _progress += 1 / imports.length;
      });
      final file = entry.key;
      final imageCode = entry.value;

      try {
        var mxcFile = MatrixImageFile(bytes: file.content, name: file.name);

        final thumbnail = (await mxcFile.generateThumbnail(
          nativeImplementations: ClientManager.nativeImplementations,
        ));
        if (thumbnail == null) {
          Logs().w('Unable to create thumbnail');
        } else {
          mxcFile = thumbnail;
        }
        final uri = await Matrix.of(context).client.uploadContent(
          mxcFile.bytes,
          filename: mxcFile.name,
          contentType: mxcFile.mimeType,
        );

        // Keep the actual generated image metadata. MSC2545 does not require
        // 256x256 sticker metadata (and recommends stickers are at least
        // 512x512), so rewriting dimensions here would make `info` inaccurate.
        final info = <String, dynamic>{...mxcFile.info};
        widget.controller.pack!.images[imageCode] =
            ImagePackImageContent.fromJson(<String, dynamic>{
              'url': uri.toString(),
              'info': info,
            });
        successfulUploads.add(file.name);
      } catch (e) {
        Logs().d('Could not upload emote $imageCode');
      }
    }

    await widget.controller.save(context);
    _importMap.removeWhere(
      (key, value) => successfulUploads.contains(key.name),
    );

    _loading = false;
    _progress = 0;

    // in case we have unhandled / duplicated emotes left, don't pop
    if (mounted) setState(() {});
    if (_importMap.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(context).pop(),
      );
    }
  }
}

class _EmojiImportPreview extends StatefulWidget {
  final MapEntry<ArchiveFile, String> entry;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onRemove;

  const _EmojiImportPreview({
    super.key,
    required this.entry,
    required this.onNameChanged,
    required this.onRemove,
  });

  @override
  State<_EmojiImportPreview> createState() => _EmojiImportPreviewState();
}

class _EmojiImportPreviewState extends State<_EmojiImportPreview> {
  final hasErrorNotifier = ValueNotifier(false);

  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.text = widget.entry.value;
  }

  @override
  void dispose() {
    hasErrorNotifier.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          onPressed: widget.onRemove,
          icon: const Icon(Icons.remove_circle),
          tooltip: L10n.of(context).remove,
        ),
        ValueListenableBuilder(
          valueListenable: hasErrorNotifier,
          builder: (context, hasError, child) {
            if (hasError) return _ImageFileError(name: widget.entry.key.name);

            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.memory(
                  widget.entry.key.content,
                  height: 64,
                  width: 64,
                  errorBuilder: (context, e, s) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _setRenderError(),
                    );

                    return _ImageFileError(name: widget.entry.key.name);
                  },
                ),
                SizedBox(
                  width: 128,
                  child: TextField(
                    controller: controller,
                    inputFormatters: [
                      // Stable MSC2545 accepts only ASCII letters, digits,
                      // `_` and `-`, and limits shortcodes to 100 bytes.
                      FilteringTextInputFormatter.allow(
                        emoteShortcodeAllowedCharacters,
                      ),
                      LengthLimitingTextInputFormatter(maxEmoteShortcodeBytes),
                    ],
                    autocorrect: false,
                    minLines: 1,
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: L10n.of(context).emoteShortcode,
                      prefixText: ': ',
                      suffixText: ':',
                      border: const OutlineInputBorder(),
                      prefixStyle: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                      suffixStyle: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onChanged: widget.onNameChanged,
                    onSubmitted: widget.onNameChanged,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _setRenderError() {
    hasErrorNotifier.value = true;
    widget.onRemove.call();
  }
}

class _ImageFileError extends StatelessWidget {
  final String name;

  const _ImageFileError({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox.square(
      dimension: 64,
      child: Tooltip(
        message: name,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.error),
            Text(
              L10n.of(context).notAnImage,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  /// Normalizes a file path into an MSC2545-compatible image-pack shortcode.
  ///
  /// The file extension is removed first, then unsupported characters are
  /// replaced and the result is capped at the stable 100-byte limit.
  String get emoteNameFromPath {
    final name = split(RegExp(r'[/\\]')).last.split('.').first.toLowerCase();
    return sanitizeEmoteShortcode(name);
  }
}
