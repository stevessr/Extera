import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/rich_presence.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/mxc_image.dart';

class RichPresenceContent extends StatefulWidget {
  final List<RichPresenceEntry> presences;
  final bool noBackground;
  final bool noPadding;
  final bool single;

  const RichPresenceContent({
    required this.presences,
    this.noBackground = false,
    this.noPadding = false,
    this.single = false,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RichPresenceContentState();
}

class _RichPresenceContentState extends State<RichPresenceContent> {
  bool minimized = true;

  @override
  Widget build(BuildContext context) {
    if (widget.presences.isEmpty) return const SizedBox.shrink();
    final presences = widget.presences.take(minimized ? 1 : 4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        for (final entry in presences)
          _PresenceCard(
            entry: entry,
            noBackground: widget.noBackground,
            noPadding: widget.noPadding,
          ),
        if (widget.presences.length > 1 && !widget.single && minimized)
          TextButton(
            onPressed: () {
              setState(() {
                minimized = false;
              });
            },
            child: Text(L10n.of(context).loadMore),
          ),
      ],
    );
  }
}

class _PresenceCard extends StatelessWidget {
  final RichPresenceEntry entry;
  final bool noBackground;
  final bool noPadding;

  const _PresenceCard({
    required this.entry,
    required this.noBackground,
    required this.noPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      clipBehavior: Clip.hardEdge,
      color: noBackground
          ? Colors.transparent
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Padding(
        padding: EdgeInsets.all(noPadding ? 0 : 16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                entry.type == RichPresenceType.music
                    ? entry.playerName != null
                          ? L10n.of(context).listeningTo(entry.playerName!)
                          : L10n.of(context).listeningToSomeTunes
                    : L10n.of(context).playing,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                _buildIconBlock(context, theme),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entry.type == RichPresenceType.music
                        ? _buildMusicInfo(context)
                        : _buildActivityInfo(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconBlock(BuildContext context, ThemeData theme) {
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius / 2);

    if (entry.type == RichPresenceType.music) {
      return Material(
        clipBehavior: .hardEdge,
        borderRadius: borderRadius,
        color: theme.colorScheme.surfaceContainerHigh,
        child: entry.coverUrl != null
            ? MxcImage(
                uri: entry.coverUrl,
                width: 128,
                height: 128,
                isThumbnail: true,
                thumbnailMethod: .scale,
              )
            : SizedBox(
                width: 128,
                height: 128,
                child: Icon(Icons.music_note, size: 48),
              ),
      );
    }

    final largeIconUrl = entry.largeIconUrl;
    if (largeIconUrl == null) {
      return Material(
        clipBehavior: .hardEdge,
        borderRadius: borderRadius,
        color: theme.colorScheme.surfaceContainerHigh,
        child: SizedBox(
          width: 128,
          height: 128,
          child: Icon(Icons.games_rounded, size: 48),
        ),
      );
    }

    final smallIconUrl = entry.smallIconUrl;
    return Material(
      clipBehavior: .hardEdge,
      borderRadius: borderRadius,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SizedBox(
        width: 128,
        height: 128,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: entry.largeIconTooltip != null
                  ? Tooltip(
                      message: entry.largeIconTooltip!,
                      child: MxcImage(
                        uri: largeIconUrl,
                        width: 128,
                        height: 128,
                        isThumbnail: true,
                        thumbnailMethod: .scale,
                      ),
                    )
                  : MxcImage(
                      uri: largeIconUrl,
                      width: 128,
                      height: 128,
                      isThumbnail: true,
                      thumbnailMethod: .scale,
                    ),
            ),
            if (smallIconUrl != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: entry.smallIconTooltip != null
                    ? Tooltip(
                        message: entry.smallIconTooltip!,
                        child: Material(
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          color: theme.colorScheme.surfaceContainerHigh,
                          child: MxcImage(
                            uri: smallIconUrl,
                            width: 36,
                            height: 36,
                            isThumbnail: true,
                            thumbnailMethod: .scale,
                          ),
                        ),
                      )
                    : Material(
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        color: theme.colorScheme.surfaceContainerHigh,
                        child: MxcImage(
                          uri: smallIconUrl,
                          width: 36,
                          height: 36,
                          isThumbnail: true,
                          thumbnailMethod: .scale,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMusicInfo(BuildContext context) {
    final children = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: Text(entry.track!, style: const TextStyle(fontSize: 18)),
      ),
      if (entry.artist != null)
        Align(alignment: Alignment.centerLeft, child: Text(entry.artist!)),
      if (entry.album != null)
        Align(alignment: Alignment.centerLeft, child: Text(entry.album!)),
      if (entry.progressSince != null && entry.progressUntil != null) ...[
        const SizedBox(height: 8),
        _PresenceTimeInfo(
          since: entry.progressSince,
          until: entry.progressUntil,
        ),
      ],
      _buildButtons(context),
    ];
    return children;
  }

  List<Widget> _buildActivityInfo(BuildContext context) {
    final children = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: Text(entry.name!, style: const TextStyle(fontSize: 18)),
      ),
      if (entry.state != null)
        Align(alignment: Alignment.centerLeft, child: Text(entry.state!)),
      if (entry.details != null)
        Align(alignment: Alignment.centerLeft, child: Text(entry.details!)),
      if (entry.since != null && entry.until != null) ...[
        const SizedBox(height: 8),
        _PresenceTimeInfo(since: entry.since, until: entry.until),
      ] else if (entry.since != null) ...[
        const SizedBox(height: 8),
        _PresenceTimeInfo(since: entry.since, until: null),
      ] else if (entry.until != null) ...[
        const SizedBox(height: 8),
        _PresenceTimeInfo(since: null, until: entry.until),
      ],
      _buildButtons(context),
    ];
    return children;
  }

  Widget _buildButtons(BuildContext context) {
    if (entry.buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const .symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final button in entry.buttons)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.open_in_new),
              label: Text(button.label),
              onPressed: () => _onButtonTap(context, button),
            ),
        ],
      ),
    );
  }
}

class _PresenceTimeInfo extends StatefulWidget {
  final int? since;
  final int? until;

  const _PresenceTimeInfo({this.since, this.until})
    : assert(since != null || until != null);

  @override
  State<_PresenceTimeInfo> createState() => _PresenceTimeInfoState();
}

class _PresenceTimeInfoState extends State<_PresenceTimeInfo> {
  late final Timer _timer;
  int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {
        _now = DateTime.now().millisecondsSinceEpoch;
      }),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final minutesPadded = minutes.toString().padLeft(2, '0');
    final secondsPadded = seconds.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutesPadded:$secondsPadded'
        : '$minutes:$secondsPadded';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final since = widget.since;
    final until = widget.until;

    if (since != null && until != null) {
      final total = until - since;
      final pos = (_now - since).clamp(0, total);
      return LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: constraints,
            child: Row(
              mainAxisSize: .min,
              crossAxisAlignment: .center,
              spacing: 8,
              children: [
                Text(_formatDuration(pos), style: theme.textTheme.bodySmall),
                Expanded(
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    trackGap: 4,
                    value: total > 0 ? pos / total : 1.0,
                  ),
                ),
                Text(_formatDuration(total), style: theme.textTheme.bodySmall),
              ],
            ),
          );
        },
      );
    }
    if (since != null) {
      return Text(
        L10n.of(context).richPresenceElapsed(
          _formatDuration((_now - since).clamp(0, 1 << 40)),
        ),
        style: theme.textTheme.bodySmall,
      );
    }
    return Text(
      L10n.of(context).richPresenceRemaining(
        _formatDuration((until! - _now).clamp(0, 1 << 40)),
      ),
      style: theme.textTheme.bodySmall,
    );
  }
}

Future<void> _onButtonTap(
  BuildContext context,
  RichPresenceButton button,
) async {
  var url = button.url;
  final confirmed = await _confirmButtonUrl(
    context,
    url,
    isOpenId: button.requestOpenid,
  );
  if (button.requestOpenid) {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.requestOpenIdToken(client.userID!, {}),
    );
    final creds = result.result;
    if (creds == null) return;
    url = button.url.replaceAll(
      '{openid_data}',
      Uri.encodeComponent(jsonEncode(creds.toJson())),
    );
  }
  if (!confirmed) return;
  await launchUrlString(url, mode: LaunchMode.externalApplication);
}

Future<bool> _confirmButtonUrl(
  BuildContext context,
  String url, {
  required bool isOpenId,
}) async {
  final result = await showAdaptiveDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (context) => AlertDialog.adaptive(
      title: Text(L10n.of(context).openLinkInBrowser),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOpenId) ...[
                Text(L10n.of(context).richPresenceOpenIdWarning),
                const SizedBox(height: 8),
              ],
              SelectableLinkify(
                text: url,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                style: Theme.of(context).textTheme.bodyMedium,
                linkStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
                options: const LinkifyOptions(humanize: false),
                onOpen: (link) => UrlLauncher(context, link.url).launchUrl(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.0),
            ),
          ),
          onPressed: () => Navigator.of(context).pop<bool>(false),
          child: Text(L10n.of(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop<bool>(true),
          autofocus: true,
          child: Text(L10n.of(context).open),
        ),
      ],
    ),
  );
  return result ?? false;
}
