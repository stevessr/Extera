import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/mxc_image.dart';

/// A link unfurling card shown below messages that consist of a single URL.
///
/// The preview data is fetched through the homeserver's `preview_url`
/// endpoint (`client.getUrlPreview`), so the client never contacts the
/// linked website directly. Servers without preview support simply yield
/// an error, which hides the card instead of surfacing it to the user.
class UrlPreviewCard extends StatefulWidget {
  const UrlPreviewCard({required this.event, required this.url, super.key});

  final Event event;
  final Uri url;

  /// Returns the single http(s) URL contained in [body], or null when the
  /// body is not essentially just that one link.
  static Uri? extractSingleLink(String body) {
    var text = body.trim();
    if (text.isEmpty) return null;
    // Edited messages carry a leading "* " marker in their rendered body.
    if (text.startsWith('* ')) text = text.substring(2);
    final matches = _linkPattern.allMatches(text).toList(growable: false);
    if (matches.length != 1) return null;
    final match = matches.single;
    // Only preview when nothing but whitespace surrounds the link.
    final remainder = text.replaceRange(match.start, match.end, '').trim();
    if (remainder.isNotEmpty) return null;
    final uri = Uri.tryParse(match[0]!);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
    return uri;
  }

  static final RegExp _linkPattern = RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  );

  /// In-memory cache keyed by URL. Failures are negative-cached as null so
  /// a server without preview support is never hammered per rebuild.
  static final Map<String, PreviewForUrl?> _cache = {};
  static const int _cacheLimit = 128;

  @override
  State<UrlPreviewCard> createState() => _UrlPreviewCardState();
}

class _UrlPreviewCardState extends State<UrlPreviewCard> {
  PreviewForUrl? _preview;
  bool _failed = false;

  static void _putCache(String key, PreviewForUrl? value) {
    if (UrlPreviewCard._cache.length >= UrlPreviewCard._cacheLimit) {
      UrlPreviewCard._cache.clear();
    }
    UrlPreviewCard._cache[key] = value;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = widget.url.toString();
    if (UrlPreviewCard._cache.containsKey(key)) {
      setState(() {
        _preview = UrlPreviewCard._cache[key];
        _failed = _preview == null;
      });
      return;
    }
    try {
      final preview = await widget.event.room.client
          .getUrlPreview(widget.url)
          .timeout(const Duration(seconds: 15));
      _putCache(key, preview);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e, s) {
      _putCache(key, null);
      Logs().d('URL preview unavailable', e, s);
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  String get _host => widget.url.host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    if (_failed || preview == null) return const SizedBox.shrink();

    final props = preview.additionalProperties;
    final title = props['og:title'] as String?;
    final description = props['og:description'] as String?;
    final siteName = props['og:site_name'] as String?;
    final image = preview.ogImage;
    // Nothing meaningful to show: hide rather than render an empty card.
    if ((title == null || title.trim().isEmpty) &&
        (description == null || description.trim().isEmpty) &&
        image == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 12, right: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => UrlLauncher(context, widget.url.toString()).launchUrl(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (image != null && image.scheme == 'mxc')
                MxcImage(
                  uri: image,
                  client: widget.event.room.client,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (title?.isNotEmpty ?? false) ? title! : _host,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.link,
                          size: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            siteName?.isNotEmpty ?? false ? siteName! : _host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
