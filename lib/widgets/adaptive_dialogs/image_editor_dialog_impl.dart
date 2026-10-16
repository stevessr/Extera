import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

// Deferred imports may not expose extension declarations, so hide them all;
// this file only constructs config/widget classes through the prefix.
import 'package:pro_image_editor/pro_image_editor.dart'
    deferred as pie
    hide FilterStateListExtension;

/// [pro_image_editor] performs no locale resolution of its own; every visible
/// string is configured through [pie.I18n]. The generated L10n arb files do
/// not cover editor strings, so Chinese translations live here and other
/// locales keep the package's English defaults.
// The return types are left unannotated: deferred types cannot be named in
// this file's declarations, and translating the config is only meaningful
// after the deferred chunk has been loaded.
dynamic _zhEditorI18n() => pie.I18n(
  importStateHistoryMsg: '正在加载编辑记录',
  cancel: '取消',
  undo: '撤销',
  redo: '重做',
  done: '完成',
  remove: '移除',
  doneLoadingMsg: '正在应用更改',
  various: pie.I18nVarious(
    loadingDialogMsg: '请稍候…',
    closeEditorWarningTitle: '关闭图片编辑器？',
    closeEditorWarningMessage: '尚未保存的更改将会丢失，仍要关闭吗？',
    closeEditorWarningConfirmBtn: '关闭',
    closeEditorWarningCancelBtn: '取消',
  ),
  paintEditor: pie.I18nPaintEditor(
    bottomNavigationBarText: '绘图',
    moveAndZoom: '移动与缩放',
    freestyle: '手绘',
    freestyleArrowStart: '手绘箭头起点',
    freestyleArrowEnd: '手绘箭头终点',
    freestyleArrowStartEnd: '手绘箭头双向',
    arrow: '箭头',
    line: '直线',
    rectangle: '矩形',
    circle: '圆形',
    dashLine: '虚线',
    dashDotLine: '点划线',
    hexagon: '六边形',
    polygon: '多边形',
    blur: '涂抹模糊',
    pixelate: '像素化',
    custom1: '自定义 1',
    custom2: '自定义 2',
    custom3: '自定义 3',
    eraser: '橡皮擦',
    lineWidth: '线宽',
    toggleFill: '切换填充',
    changeOpacity: '更改透明度',
    opacity: '透明度',
    color: '颜色',
    strokeWidth: '描边粗细',
    fill: '填充',
    back: '返回',
    smallScreenMoreTooltip: '更多',
  ),
  textEditor: pie.I18nTextEditor(
    inputHintText: '输入文字',
    bottomNavigationBarText: '文字',
    textAlign: '文字对齐',
    fontScale: '字号',
    backgroundMode: '背景样式',
    back: '返回',
    done: '完成',
    smallScreenMoreTooltip: '更多',
  ),
  cropRotateEditor: pie.I18nCropRotateEditor(
    bottomNavigationBarText: '裁剪/旋转',
    rotate: '旋转',
    flip: '翻转',
    tilt: '倾斜',
    tiltRotate: '倾斜旋转',
    tiltHorizontal: '水平',
    tiltVertical: '垂直',
    ratio: '比例',
    reset: '重置',
    back: '返回',
    smallScreenMoreTooltip: '更多',
  ),
  tuneEditor: pie.I18nTuneEditor(
    bottomNavigationBarText: '调节',
    brightness: '亮度',
    contrast: '对比度',
    saturation: '饱和度',
    exposure: '曝光',
    hue: '色相',
    temperature: '色温',
    fade: '褪色',
    tint: '色调',
    back: '返回',
    done: '完成',
    undo: '撤销',
    redo: '重做',
  ),
  filterEditor: pie.I18nFilterEditor(
    bottomNavigationBarText: '滤镜',
    back: '返回',
    done: '完成',
    filters: pie.I18nFilters(none: '无滤镜'),
  ),
  blurEditor: pie.I18nBlurEditor(
    bottomNavigationBarText: '模糊',
    back: '返回',
    done: '完成',
  ),
  emojiEditor: pie.I18nEmojiEditor(
    bottomNavigationBarText: '表情',
    search: '搜索',
    categoryRecent: '最近使用',
    categorySmileys: '笑脸与人物',
    categoryAnimals: '动物与自然',
    categoryFood: '食物与饮品',
    categoryActivities: '活动',
    categoryTravel: '旅行与地点',
    categoryObjects: '物品',
    categorySymbols: '符号',
    categoryFlags: '旗帜',
  ),
  stickerEditor: pie.I18nStickerEditor(bottomNavigationBarText: '贴纸'),
  layerInteraction: pie.I18nLayerInteraction(
    remove: '移除',
    edit: '编辑',
    rotateScale: '旋转与缩放',
  ),
);

dynamic _zhHantEditorI18n() => pie.I18n(
  importStateHistoryMsg: '正在載入編輯記錄',
  cancel: '取消',
  undo: '復原',
  redo: '重做',
  done: '完成',
  remove: '移除',
  doneLoadingMsg: '正在套用變更',
  various: pie.I18nVarious(
    loadingDialogMsg: '請稍候…',
    closeEditorWarningTitle: '關閉圖片編輯器？',
    closeEditorWarningMessage: '尚未儲存的變更將會遺失，仍要關閉嗎？',
    closeEditorWarningConfirmBtn: '關閉',
    closeEditorWarningCancelBtn: '取消',
  ),
  paintEditor: pie.I18nPaintEditor(
    bottomNavigationBarText: '繪圖',
    moveAndZoom: '移動與縮放',
    freestyle: '手繪',
    freestyleArrowStart: '手繪箭頭起點',
    freestyleArrowEnd: '手繪箭頭終點',
    freestyleArrowStartEnd: '手繪箭頭雙向',
    arrow: '箭頭',
    line: '直線',
    rectangle: '矩形',
    circle: '圓形',
    dashLine: '虛線',
    dashDotLine: '點劃線',
    hexagon: '六邊形',
    polygon: '多邊形',
    blur: '塗抹模糊',
    pixelate: '像素化',
    custom1: '自訂 1',
    custom2: '自訂 2',
    custom3: '自訂 3',
    eraser: '橡皮擦',
    lineWidth: '線寬',
    toggleFill: '切換填滿',
    changeOpacity: '變更透明度',
    opacity: '透明度',
    color: '顏色',
    strokeWidth: '描邊粗細',
    fill: '填滿',
    back: '返回',
    smallScreenMoreTooltip: '更多',
  ),
  textEditor: pie.I18nTextEditor(
    inputHintText: '輸入文字',
    bottomNavigationBarText: '文字',
    textAlign: '文字對齊',
    fontScale: '字號',
    backgroundMode: '背景樣式',
    back: '返回',
    done: '完成',
    smallScreenMoreTooltip: '更多',
  ),
  cropRotateEditor: pie.I18nCropRotateEditor(
    bottomNavigationBarText: '裁切/旋轉',
    rotate: '旋轉',
    flip: '翻轉',
    tilt: '傾斜',
    tiltRotate: '傾斜旋轉',
    tiltHorizontal: '水平',
    tiltVertical: '垂直',
    ratio: '比例',
    reset: '重設',
    back: '返回',
    smallScreenMoreTooltip: '更多',
  ),
  tuneEditor: pie.I18nTuneEditor(
    bottomNavigationBarText: '調整',
    brightness: '亮度',
    contrast: '對比',
    saturation: '飽和度',
    exposure: '曝光',
    hue: '色相',
    temperature: '色溫',
    fade: '褪色',
    tint: '色調',
    back: '返回',
    done: '完成',
    undo: '復原',
    redo: '重做',
  ),
  filterEditor: pie.I18nFilterEditor(
    bottomNavigationBarText: '濾鏡',
    back: '返回',
    done: '完成',
    filters: pie.I18nFilters(none: '無濾鏡'),
  ),
  blurEditor: pie.I18nBlurEditor(
    bottomNavigationBarText: '模糊',
    back: '返回',
    done: '完成',
  ),
  emojiEditor: pie.I18nEmojiEditor(
    bottomNavigationBarText: '表情',
    search: '搜尋',
    categoryRecent: '最近使用',
    categorySmileys: '笑臉與人物',
    categoryAnimals: '動物與自然',
    categoryFood: '食物與飲品',
    categoryActivities: '活動',
    categoryTravel: '旅行與地點',
    categoryObjects: '物品',
    categorySymbols: '符號',
    categoryFlags: '旗幟',
  ),
  stickerEditor: pie.I18nStickerEditor(bottomNavigationBarText: '貼圖'),
  layerInteraction: pie.I18nLayerInteraction(
    remove: '移除',
    edit: '編輯',
    rotateScale: '旋轉與縮放',
  ),
);

/// Returns editor translations for the active app locale; Chinese is fully
/// covered, everything else falls back to the package's English defaults.
dynamic _editorI18n(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  if (locale == null) return pie.I18n();
  switch (locale.languageCode) {
    case 'zh':
      return locale.scriptCode == 'Hant'
          ? _zhHantEditorI18n()
          : _zhEditorI18n();
    default:
      return pie.I18n();
  }
}

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
            i18n: _editorI18n(context),
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
