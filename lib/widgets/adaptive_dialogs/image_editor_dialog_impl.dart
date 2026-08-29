import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:google_fonts/google_fonts.dart';

// Deferred imports may not expose extension declarations, so hide them all;
// this file only constructs config/widget classes through the prefix.
import 'package:pro_image_editor/pro_image_editor.dart'
    deferred as pie
    hide FilterStateListExtension;

class MaterialYouEditor extends StatefulWidget {
  /// Creates a new [MaterialYouEditor] widget.
  const MaterialYouEditor({
    super.key,
    required this.byteArray,
    required this.onImageEditingComplete,
  });

  /// The URL of the image to display.
  final Uint8List byteArray;
  final Future<void> Function(Uint8List) onImageEditingComplete;

  @override
  State<MaterialYouEditor> createState() => _MaterialYouEditorState();
}

class _MaterialYouEditorState extends State<MaterialYouEditor> {
  /// Calculates the number of columns for the EmojiPicker.
  int _calculateEmojiColumns(BoxConstraints constraints) =>
      max(1, 6 / 400 * constraints.maxWidth - 1).floor();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return pie.ProImageEditor.memory(
          widget.byteArray,
          callbacks: pie.ProImageEditorCallbacks(
            onImageEditingComplete: widget.onImageEditingComplete,
          ),
          configs: pie.ProImageEditorConfigs(
            designMode: pie.ImageEditorDesignMode.material,
            theme: Theme.of(context),
            paintEditor: pie.PaintEditorConfigs(
              style: pie.PaintEditorStyle(initialStrokeWidth: 5),
            ),
            textEditor: pie.TextEditorConfigs(
              customTextStyles: [
                GoogleFonts.roboto(),
                GoogleFonts.averiaLibre(),
                GoogleFonts.lato(),
                GoogleFonts.comicNeue(),
                GoogleFonts.actor(),
                GoogleFonts.odorMeanChey(),
                GoogleFonts.nabla(),
              ],
            ),
            cropRotateEditor: pie.CropRotateEditorConfigs(),
            filterEditor: pie.FilterEditorConfigs(
              style: pie.FilterEditorStyle(
                filterListSpacing: 7,
                filterListMargin: EdgeInsets.fromLTRB(8, 15, 8, 10),
              ),
            ),
            tuneEditor: pie.TuneEditorConfigs(),
            blurEditor: pie.BlurEditorConfigs(),
            emojiEditor: pie.EmojiEditorConfigs(
              checkPlatformCompatibility: !kIsWeb,
              style: pie.EmojiEditorStyle(
                emojiViewConfig: pie.EmojiViewConfig(
                  gridPadding: EdgeInsets.zero,
                  horizontalSpacing: 0,
                  verticalSpacing: 0,
                  recentsLimit: 40,
                  buttonMode: pie.ButtonMode.MATERIAL,
                  loadingIndicator: const Center(
                    child: CircularProgressIndicator(),
                  ),
                  columns: _calculateEmojiColumns(constraints),
                  emojiSizeMax: 64,
                  replaceEmojiOnLimitExceed: false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const String _iconsFamily = 'packages/pro_image_editor/ProImageEditorIcons';
const String _iconsAsset =
    'assets/packages/pro_image_editor/assets/fonts/ProImageEditorIcons.ttf';

Future<void>? _iconsLoaded;

/// The icon font is stripped from FontManifest.json by the release pipeline
/// (scripts/strip-katex-manifest.py) so the engine does not preload ~1 MB
/// for a one-off feature; register it here before the editor renders.
Future<void> ensureProImageEditorIconsLoaded() => _iconsLoaded ??= _loadIcons();

Future<void> _loadIcons() async {
  try {
    final manifest = await rootBundle.loadString('FontManifest.json');
    if (manifest.contains('"$_iconsFamily"')) return;
    final loader = FontLoader(_iconsFamily);
    loader.addFont(rootBundle.load(_iconsAsset));
    await loader.load();
  } catch (_) {
    // Unstripped builds already register the family via the manifest; any
    // other failure just falls back to tofu icons instead of crashing.
  }
}

Future<Uint8List?> showImageEditor({
  required BuildContext context,
  required Uint8List byteArray,
}) async {
  // The editor is a large one-off feature; keep it out of the startup bundle
  // on the web (JS fallback splits it into a lazily fetched part file).
  await Future.wait([pie.loadLibrary(), ensureProImageEditorIconsLoaded()]);
  return showAdaptiveDialog<Uint8List>(
    context: context,
    useSafeArea: true,
    builder: (context) => MaterialYouEditor(
      byteArray: byteArray,
      onImageEditingComplete: (bytes) async {
        Navigator.of(context).pop<Uint8List>(bytes);
      },
    ),
  );
}
