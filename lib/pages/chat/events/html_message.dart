import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:highlight_selectable/highlight_selectable.dart';
import 'package:highlight_selectable/theme_map.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:linkify/linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/utils/katex_fonts.dart';
import 'package:extera_next/utils/latex_renderer.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/message_selection_area.dart';
import 'package:extera_next/widgets/mxc_image.dart';

import '../../../utils/url_launcher.dart';

class HtmlMessage extends StatefulWidget {
  final String html;
  final Room room;
  final Color textColor;
  final double fontSize;
  final TextStyle linkStyle;
  final bool bigEmotes;

  final void Function(LinkableElement) onOpen;
  final void Function() onCopy;

  final bool selectable;

  final InlineSpan? trailingSpan;

  /// Called when the message text is right clicked, so that the message
  /// context menu can be opened instead of the text selection toolbar.
  final void Function(Offset globalPosition)? onSecondaryTap;

  const HtmlMessage({
    super.key,
    required this.html,
    required this.room,
    required this.fontSize,
    required this.linkStyle,
    this.textColor = Colors.black,
    required this.onOpen,
    required this.onCopy,
    this.selectable = false,
    this.bigEmotes = false,
    this.trailingSpan,
    this.onSecondaryTap,
  });

  /// Keep in sync with: https://spec.matrix.org/latest/client-server-api/#mroommessage-msgtypes
  static const Set<String> allowedHtmlTags = {
    'font',
    'del',
    's',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'p',
    'a',
    'ul',
    'ol',
    'sup',
    'sub',
    'li',
    'b',
    'i',
    'u',
    'strong',
    'em',
    'strike',
    'code',
    'hr',
    'br',
    'div',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'caption',
    'pre',
    'span',
    'img',
    'details',
    'summary',
    // Not in the allowlist of the matrix spec yet but should be harmless:
    'ruby',
    'rp',
    'rt',
    'html',
    'body',
    // tg-forward will be rendered without formatting otherwise
    'tg-forward',
  };

  static const Set<String> ignoredHtmlTags = {'mx-reply'};

  // We add line breaks before these tags:
  static const Set<String> blockHtmlTags = {
    'p',
    'ul',
    'ol',
    'pre',
    'div',
    'table',
    'details',
    'blockquote',
  };

  // And these tags:
  static const Set<String> fullLineHtmlTag = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
  };

  @override
  State<HtmlMessage> createState() => _HtmlMessageState();
}

/// Memoized [linkify] results. Linkification is a pure text-to-elements
/// mapping with no styling or theme dependency, so its output can be shared
/// across rebuilds and widget instances; only the (cheap) span mapping runs
/// per build. Bounded LRU keyed by the raw text.
const int _linkifyCacheMaxEntries = 512;
final Map<String, List<LinkifyElement>> _linkifyCache = {};

List<LinkifyElement> _linkifyCached(String text) {
  final cached = _linkifyCache.remove(text);
  if (cached != null) {
    _linkifyCache[text] = cached;
    return cached;
  }
  final elements = linkify(
    text,
    options: const LinkifyOptions(humanize: false),
  );
  if (_linkifyCache.length >= _linkifyCacheMaxEntries) {
    _linkifyCache.remove(_linkifyCache.keys.first);
  }
  _linkifyCache[text] = elements;
  return elements;
}

class _HtmlMessageState extends State<HtmlMessage> {
  final Map<int, bool> _detailsOpenState = {};
  final Map<int, bool> _spoilerRevealedState = {};

  int _detailsCounter = 0;
  int _spoilerCounter = 0;

  String get html => widget.html;
  Room get room => widget.room;
  Color get textColor => widget.textColor;
  double get fontSize => widget.fontSize;
  TextStyle get linkStyle => widget.linkStyle;
  void Function(LinkableElement) get onOpen => widget.onOpen;

  TextStyle get _baseTextStyle => TextStyle(
    fontSize: fontSize,
    color: textColor,
    fontFamily: AppSettings.systemFont.value
        ? 'SystemFont'
        : AppSettings.chatFont.value.isNotEmpty
        ? AppSettings.systemFont.value
              ? 'SystemFont'
              : AppSettings.chatFont.value
        : null,
    fontFamilyFallback: AppSettings.fontFallback(
      AppSettings.chatFallbackFonts,
      colorEmojiFirst: true,
    ),
  );

  // to fix issue 7
  //
  /// Links are rendered as [TextSpan]s with a [TapGestureRecognizer] — the
  /// same pattern the plain-text path uses — instead of
  /// `WidgetSpan(GestureDetector(...))`: inline widget gestures are
  /// unreliable on touch devices (links stay dead on Android), while span
  /// recognizers are handled by the text pipeline everywhere.
  TextSpan _buildLinkifySpan(BuildContext context, {required String text}) {
    final elements = _linkifyCached(text);
    return TextSpan(
      children: elements.map((element) {
        if (element is LinkableElement) {
          return TextSpan(
            text: element.text,
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => onOpen(element),
          );
        } else {
          return TextSpan(
            children: buildAnimatedEmojiSpans(element.text, fontSize: fontSize),
          );
        }
      }).toList(),
    );
  }

  List<InlineSpan> _renderWithLineBreaks(
    dom.NodeList nodes,
    BuildContext context, {
    int depth = 1,
    bool insideAnchor = false,
  }) {
    final onlyElements = nodes.whereType<dom.Element>().toList();
    return [
      for (var i = 0; i < nodes.length; i++) ...[
        if (nodes[i] is dom.Element &&
            (nodes[i] as dom.Element).localName == 'blockquote')
          const TextSpan(text: '\n', style: TextStyle(fontSize: 1)),
        // Actually render the node child:
        _renderHtml(
          nodes[i],
          context,
          depth: depth + 1,
          insideAnchor: insideAnchor,
        ),
        // Add linebreaks between blocks:
        if (nodes[i] is dom.Element &&
            onlyElements.indexOf(nodes[i] as dom.Element) <
                onlyElements.length - 1) ...[
          if (HtmlMessage.blockHtmlTags.contains(
            (nodes[i] as dom.Element).localName,
          ))
            const TextSpan(text: '\n\n'),
          if (HtmlMessage.fullLineHtmlTag.contains(
            (nodes[i] as dom.Element).localName,
          ))
            const TextSpan(text: '\n'),
        ],
      ],
    ];
  }

  InlineSpan _renderHtml(
    dom.Node node,
    BuildContext context, {
    int depth = 1,
    bool insideAnchor = false,
  }) {
    if (depth >= 100) return const TextSpan();

    if (node is dom.Element &&
        HtmlMessage.ignoredHtmlTags.contains(node.localName)) {
      return const TextSpan();
    }

    if (node is! dom.Element ||
        !HtmlMessage.allowedHtmlTags.contains(node.localName)) {
      var text = node.text ?? '';

      final parentTag = node.parent?.localName;
      if (const {
            'ul',
            'ol',
            'li',
            'table',
            'thead',
            'tbody',
            'tr',
          }.contains(parentTag) &&
          text.trim().isEmpty) {
        return const TextSpan();
      }

      text = text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return const TextSpan();

      return insideAnchor
          ? TextSpan(
              children: buildAnimatedEmojiSpans(text, fontSize: fontSize),
            )
          : _buildLinkifySpan(context, text: text);
    }

    switch (node.localName) {
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        if (href == null) continue block;
        final matrixId = node.attributes['href']
            ?.parseIdentifierIntoParts()
            ?.primaryIdentifier;
        if (matrixId != null) {
          if (matrixId.sigil == '@') {
            final user = room.unsafeGetUserFromMemoryOrFallback(matrixId);
            return WidgetSpan(
              child: MatrixPill(
                key: Key('user_pill_$matrixId'),
                name: user.calcDisplayname(),
                avatar: user.avatarUrl,
                uri: href,
                outerContext: context,
                fontSize: fontSize,
                color: linkStyle.color,
              ),
            );
          }
          if (matrixId.sigil == '#' || matrixId.sigil == '!') {
            final room = matrixId.sigil == '!'
                ? this.room.client.getRoomById(matrixId)
                : this.room.client.getRoomByAlias(matrixId);
            return WidgetSpan(
              child: MatrixPill(
                name: room?.getLocalizedDisplayname() ?? matrixId,
                avatar: room?.avatar,
                uri: href,
                outerContext: context,
                fontSize: fontSize,
                color: linkStyle.color,
                withEventLink: href.contains('/\$'),
              ),
            );
          }
        }
        // Text-only anchors render as a plain [TextSpan] with a tap
        // recognizer: inline-widget gestures (WidgetSpan + InkWell) are
        // unreliable on touch devices. Anchors containing elements (images,
        // line breaks, ...) keep the widget-based rendering below.
        if (node.nodes.every((child) => child is! dom.Element)) {
          TapGestureRecognizer makeRecognizer() =>
              TapGestureRecognizer()
                ..onTap = () =>
                    UrlLauncher(context, href, node.text).launchUrl();
          // The recognizer only covers the text carried by its own span, so
          // it must sit on the same span as the link text — a textless parent
          // span would never fire.
          final emojiSpans = buildAnimatedEmojiSpans(
            node.text,
            fontSize: fontSize,
          );
          return TextSpan(
            style: linkStyle,
            children: [
              for (final span in emojiSpans)
                span is TextSpan
                    ? TextSpan(
                        text: span.text,
                        style: span.style,
                        recognizer: makeRecognizer(),
                      )
                    : span,
            ],
          );
        }
        return WidgetSpan(
          child: Tooltip(
            message: href,
            child: InkWell(
              splashColor: Colors.transparent,
              onTap: () => UrlLauncher(context, href, node.text).launchUrl(),
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: href));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
                );
              },
              child: Text.rich(
                TextSpan(
                  children: _renderWithLineBreaks(
                    node.nodes,
                    context,
                    depth: depth,
                    insideAnchor: true,
                  ),
                  style: linkStyle,
                ),
                style: _baseTextStyle.copyWith(height: 1.2),
              ),
            ),
          ),
        );
      case 'li':
        if (!{'ol', 'ul'}.contains(node.parent?.localName)) {
          continue block;
        }
        return WidgetSpan(
          child: Padding(
            padding: EdgeInsets.only(left: fontSize),
            child: Text.rich(
              TextSpan(
                children: [
                  if (node.parent?.localName == 'ul')
                    const TextSpan(text: '• '),
                  if (node.parent?.localName == 'ol')
                    TextSpan(
                      text:
                          '${(node.parent?.nodes.whereType<dom.Element>().toList().indexOf(node) ?? 0) + (int.tryParse(node.parent?.attributes['start'] ?? '1') ?? 1)}. ',
                    ),
                  ..._renderWithLineBreaks(node.nodes, context, depth: depth),
                ],
                style: _baseTextStyle,
              ),
            ),
          ),
        );
      case 'blockquote':
        return WidgetSpan(
          child: Container(
            padding: const EdgeInsets.only(left: 8.0),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: textColor, width: 5)),
            ),
            child: Text.rich(
              TextSpan(
                children: _renderWithLineBreaks(
                  node.nodes,
                  context,
                  depth: depth,
                ),
              ),
              style: _baseTextStyle,
            ),
          ),
        );
      case 'code':
        final isInline = node.parent?.localName != 'pre';
        return isInline
            ? TextSpan(
                text: node.text,
                style: TextStyle(
                  fontFamily: AppSettings.monospaceFont.value,
                  fontFamilyFallback: AppSettings.fontFallback(
                    AppSettings.monospaceFallbackFonts,
                    colorEmojiFirst: true,
                  ),
                ),
              )
            : WidgetSpan(
                child: HighlightSelectable(
                  node.text,
                  language:
                      node.className
                          .split(' ')
                          .singleWhereOrNull(
                            (className) => className.startsWith('language-'),
                          )
                          ?.split('language-')
                          .last ??
                      'md',
                  theme: themeMap['shades-of-purple']!,
                  selectable: true,
                  showCopyButton: true,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  textStyle: TextStyle(
                    fontFamily: AppSettings.monospaceFont.value,
                    fontFamilyFallback: AppSettings.fontFallback(
                      AppSettings.monospaceFallbackFonts,
                      colorEmojiFirst: true,
                    ),
                  ),
                ),
              );
      case 'img':
        final mxcUrl = Uri.tryParse(node.attributes['src'] ?? '');
        if (mxcUrl == null || mxcUrl.scheme != 'mxc') {
          return TextSpan(text: node.attributes['alt']);
        }

        final width = double.tryParse(node.attributes['width'] ?? '');
        final height = double.tryParse(node.attributes['height'] ?? '');
        const defaultDimension = 64.0;
        var actualWidth = width ?? height ?? defaultDimension;
        var actualHeight = height ?? width ?? defaultDimension;

        if (node.attributes.containsKey('data-mx-emoticon')) {
          actualWidth *= AppSettings.fontSizeFactor.value;
          actualHeight *= AppSettings.fontSizeFactor.value;

          if (actualHeight <= 24 && widget.bigEmotes) {
            final scale = 48 / actualHeight;
            actualWidth *= scale;
            actualHeight *= scale;
          }
        }

        final ratio = actualWidth / actualHeight;
        if (actualHeight > 256) {
          actualHeight = 256;
          actualWidth = actualHeight * ratio;
        }

        return WidgetSpan(
          child: SizedBox(
            width: actualWidth,
            height: actualHeight,
            child: MxcImage(
              uri: mxcUrl,
              width: actualWidth,
              height: actualHeight,
              animated: true,
              isThumbnail: false,
            ),
          ),
        );
      case 'table':
        return WidgetSpan(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: textColor.withAlpha(100)),
              children: node.nodes
                  .whereType<dom.Element>()
                  .expand(
                    (e) =>
                        e.localName == 'thead' ||
                            e.localName == 'tbody' ||
                            e.localName == 'tfoot'
                        ? e.nodes.whereType<dom.Element>()
                        : [e],
                  )
                  .where((e) => e.localName == 'tr')
                  .map(
                    (tr) => TableRow(
                      children: tr.nodes
                          .whereType<dom.Element>()
                          .where(
                            (e) => e.localName == 'td' || e.localName == 'th',
                          )
                          .map(
                            (cell) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              child: Text.rich(
                                TextSpan(
                                  children: _renderWithLineBreaks(
                                    cell.nodes,
                                    context,
                                    depth: depth,
                                  ),
                                  style: cell.localName == 'th'
                                      ? const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        )
                                      : null,
                                ),
                                style: _baseTextStyle,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      case 'thead':
      case 'tbody':
      case 'tfoot':
      case 'tr':
      case 'th':
      case 'td':
      case 'caption':
        return TextSpan(
          children: _renderWithLineBreaks(node.nodes, context, depth: depth),
        );
      case 'hr':
        return const WidgetSpan(child: Divider());
      case 'details':
        final index = _detailsCounter++;
        final isOpen = _detailsOpenState[index] ?? false;
        return WidgetSpan(
          child: InkWell(
            splashColor: Colors.transparent,
            onTap: () => setState(() {
              _detailsOpenState[index] = !isOpen;
            }),
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    child: Icon(
                      isOpen ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: fontSize * 1.2,
                      color: textColor,
                    ),
                  ),
                  if (!isOpen)
                    ...node.nodes
                        .where(
                          (node) =>
                              node is dom.Element &&
                              node.localName == 'summary',
                        )
                        .map((node) => _renderHtml(node, context, depth: depth))
                  else
                    ..._renderWithLineBreaks(node.nodes, context, depth: depth),
                ],
              ),
              style: _baseTextStyle,
            ),
          ),
        );
      case 'div':
        if (node.attributes.containsKey('data-mx-maths') &&
            AppSettings.latexMath.value) {
          final maths = node.attributes['data-mx-maths']!;
          return WidgetSpan(
            child: InkWell(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: maths));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
                );
              },
              child: LatexSpan(
                math: maths,
                fontSize: fontSize,
                color: textColor,
              ),
            ),
          );
        } else {
          continue block;
        }
      case 'span':
        if (node.attributes.containsKey('data-mx-maths') &&
            AppSettings.latexMath.value) {
          final maths = node.attributes['data-mx-maths']!;
          return WidgetSpan(
            child: InkWell(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: maths));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
                );
              },
              child: LatexSpan(
                math: maths,
                fontSize: fontSize,
                color: textColor,
              ),
            ),
          );
        }
        if (!node.attributes.containsKey('data-mx-spoiler')) {
          continue block;
        }
        final index = _spoilerCounter++;
        final isRevealed = _spoilerRevealedState[index] ?? false;
        return WidgetSpan(
          child: InkWell(
            splashColor: Colors.transparent,
            onTap: () => setState(() {
              _spoilerRevealedState[index] = !isRevealed;
            }),
            child: Text.rich(
              TextSpan(
                children: _renderWithLineBreaks(
                  node.nodes,
                  context,
                  depth: depth,
                ),
              ),
              style: _baseTextStyle.copyWith(
                backgroundColor: isRevealed ? null : textColor,
              ),
            ),
          ),
        );
      block:
      default:
        return TextSpan(
          style: switch (node.localName) {
            'body' => _baseTextStyle,
            'a' => linkStyle,
            'strong' => const TextStyle(fontWeight: FontWeight.bold),
            'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
            'del' || 's' || 'strikethrough' => TextStyle(
              decoration: TextDecoration.lineThrough,
              decorationColor: textColor,
            ),
            'u' => const TextStyle(decoration: TextDecoration.underline),
            'h1' => _baseTextStyle.copyWith(
              fontSize: fontSize * 1.6,
              height: 2,
            ),
            'h2' => _baseTextStyle.copyWith(
              fontSize: fontSize * 1.5,
              height: 2,
            ),
            'h3' => _baseTextStyle.copyWith(
              fontSize: fontSize * 1.4,
              height: 2,
            ),
            'h4' => _baseTextStyle.copyWith(
              fontSize: fontSize * 1.3,
              height: 1.75,
            ),
            'h5' => _baseTextStyle.copyWith(
              fontSize: fontSize * 1.2,
              height: 1.75,
            ),
            'h6' => _baseTextStyle.copyWith(
              fontSize: fontSize * 1.1,
              height: 1.5,
            ),
            'span' => TextStyle(
              color:
                  node.attributes['color']?.hexToColor ??
                  node.attributes['data-mx-color']?.hexToColor ??
                  textColor,
              backgroundColor: node.attributes['data-mx-bg-color']?.hexToColor,
            ),
            'sup' => const TextStyle(
              fontFeatures: [FontFeature.superscripts()],
            ),
            'sub' => const TextStyle(fontFeatures: [FontFeature.subscripts()]),
            _ => null,
          },
          children: _renderWithLineBreaks(node.nodes, context, depth: depth),
        );
    }
  }

  dom.Document? _cachedParsedDocument;
  String? _cachedParsedHtml;

  dom.Document? get parsedDocument {
    if (_cachedParsedHtml != html) {
      _cachedParsedHtml = html;
      _cachedParsedDocument = parser.parse(html);
    }
    return _cachedParsedDocument;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    _detailsCounter = 0;
    _spoilerCounter = 0;

    final renderedSpan = _renderHtml(
      parsedDocument?.body ?? dom.Element.html(''),
      context,
    );
    final textSpan = widget.trailingSpan == null
        ? renderedSpan
        : TextSpan(children: [renderedSpan, widget.trailingSpan!]);
    final textStyle = _baseTextStyle;

    if (widget.selectable) {
      return MessageSelectionArea(
        onSecondaryTap: widget.onSecondaryTap,
        child: Text.rich(textSpan, style: textStyle),
      );
    }

    return Text.rich(textSpan, style: textStyle);
  }
}

class MatrixPill extends StatelessWidget {
  final String name;
  final BuildContext outerContext;
  final Uri? avatar;
  final String uri;
  final double? fontSize;
  final Color? color;
  final bool withEventLink;

  const MatrixPill({
    super.key,
    required this.name,
    required this.outerContext,
    this.avatar,
    required this.uri,
    required this.fontSize,
    required this.color,
    this.withEventLink = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      onTap: UrlLauncher(outerContext, uri).launchUrl,
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              child: Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Avatar(mxContent: avatar, name: name, size: 16),
              ),
            ),
            TextSpan(
              style: TextStyle(
                color: color,
                decoration: .none,
                fontSize: fontSize,
                height: 1.2,
                fontFamily: AppSettings.systemFont.value
                    ? 'SystemFont'
                    : AppSettings.chatFont.value.isNotEmpty
                    ? AppSettings.systemFont.value
                          ? 'SystemFont'
                          : AppSettings.chatFont.value
                    : null,
                fontFamilyFallback: AppSettings.fontFallback(
                  AppSettings.chatFallbackFonts,
                  colorEmojiFirst: true,
                ),
              ),
              children: [
                TextSpan(
                  text: name,
                  style: TextStyle(
                    color: color,
                    decoration: .none,
                    fontSize: fontSize,
                    height: 1.2,
                    fontFamily: AppSettings.systemFont.value
                        ? 'SystemFont'
                        : AppSettings.chatFont.value.isNotEmpty
                        ? AppSettings.systemFont.value
                              ? 'SystemFont'
                              : AppSettings.chatFont.value
                        : null,
                    fontFamilyFallback: AppSettings.fontFallback(
                      AppSettings.chatFallbackFonts,
                      colorEmojiFirst: true,
                    ),
                  ),
                ),
                if (withEventLink)
                  WidgetSpan(
                    baseline: TextBaseline.alphabetic,
                    alignment: PlaceholderAlignment.baseline,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        Icon(Icons.chevron_right, size: 16, color: color),
                        Icon(Icons.messenger_outline, size: 16, color: color),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void>? _latexRendererFuture;

Future<void> _loadLatexRenderer() {
  _latexRendererFuture ??= Future.wait<void>([
    ensureKaTeXFontsLoaded(),
    ensureLatexRendererLoaded(),
  ]).then((_) {});
  return _latexRendererFuture!;
}

class LatexSpan extends StatelessWidget {
  final Color color;
  final double fontSize;
  final String math;

  const LatexSpan({
    required this.math,
    required this.fontSize,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: color,
      fontSize: fontSize,
      fontFamily: AppSettings.systemFont.value
          ? 'SystemFont'
          : AppSettings.chatFont.value.isNotEmpty
          ? AppSettings.systemFont.value
                ? 'SystemFont'
                : AppSettings.chatFont.value
          : null,
      fontFamilyFallback: AppSettings.fontFallback(
        AppSettings.chatFallbackFonts,
        colorEmojiFirst: true,
      ),
    );

    // Native builds compile deferred libraries in eagerly, so LaTexT stays
    // synchronous there — important because this widget sits inside a
    // WidgetSpan: swapping a raw Text placeholder for a nested rich-text
    // layout on the next frame breaks Android line metrics.
    if (!kIsWeb) return _buildLatex(style);

    return FutureBuilder<void>(
      future: _loadLatexRenderer(),
      builder: (context, snapshot) {
        // KaTeX fonts register and the renderer chunk loads lazily on first
        // render; until then the equation glyphs would show up as tofu, so
        // show the raw code.
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(math, style: style);
        }
        return _buildLatex(style);
      },
    );
  }

  Widget _buildLatex(TextStyle style) => buildLatexWidget(
    laTeXCode: Text('\$$math\$', style: style),
    onErrorFallback: (text) => Text(text, style: style),
  );
}

extension on String {
  Color? get hexToColor {
    var hexCode = this;
    if (hexCode.startsWith('#')) hexCode = hexCode.substring(1);
    if (hexCode.length == 6) hexCode = 'FF$hexCode';
    final colorValue = int.tryParse(hexCode, radix: 16);
    return colorValue == null ? null : Color(colorValue);
  }
}
