import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/matrix.dart';

const _forwardedContentKeys = [
  'org.matrix.msc4553.forwarded', // unstable msc4553 key
  'm.forwarded', // stable key for future
  'com.famedly.app.forwarded', // legacy msc2723 key
];

Map<String, Object?> sanitizeContent(Map<String, Object?> content) {
  final allowedFields = [
    'msgtype',
    'body',
    'format',
    'formatted_body',
    'filename',
    'info',
    'url',
    'file',
  ];
  final newContent = <String, Object?>{};
  for (final field in allowedFields) {
    if (content.containsKey(field)) {
      newContent[field] = content[field];
    }
  }
  return newContent;
}

Map<String, Object?> buildForwardedObject(
  Event originalEvent,
  Event displayEvent,
) {
  for (final key in _forwardedContentKeys) {
    final previous = displayEvent.content[key];
    if (previous is Map && previous['content'] is Map) {
      return jsonDecode(jsonEncode(previous)) as Map<String, Object?>;
    }
  }

  final source =
      jsonDecode(jsonEncode(displayEvent.content)) as Map<String, Object?>;
  for (final key in _forwardedContentKeys) {
    source.remove(key);
  }
  source.remove('m.new_content');

  // Strip legacy reply fallback from forwarded content
  final relatesTo = source['m.relates_to'];
  if (relatesTo is Map && relatesTo.containsKey('m.in_reply_to')) {
    final body = source['body'];
    if (body is String) {
      source['body'] = body.replaceFirst(
        RegExp(r'^>( \*)? <[^>]+>[^\n\r]+\r?\n(> [^\n]*\r?\n)*\r?\n'),
        '',
      );
    }
    final formattedBody = source['formatted_body'];
    if (formattedBody is String) {
      source['formatted_body'] = formattedBody.replaceAll(
        RegExp(r'<mx-reply>.*?</mx-reply>', dotAll: true),
        '',
      );
    }
  }

  return <String, Object?>{
    'event_id': originalEvent.eventId,
    'room_id': originalEvent.room.id,
    'sender': originalEvent.senderId,
    'origin_server_ts': originalEvent.originServerTs.millisecondsSinceEpoch,
    'content': source,
  };
}

Map<String, Object?> buildForwardContent(
  Map<String, Object?> forwarded, {
  String? senderDisplayName,
}) {
  final src = forwarded['content'] as Map<String, Object?>;
  final eventId = forwarded['event_id'] as String?;
  final roomId = forwarded['room_id'] as String?;
  final sender = forwarded['sender'] as String?;
  final permalink = roomId != null && eventId != null
      ? 'https://matrix.to/#/${Uri.encodeComponent(roomId)}/${Uri.encodeComponent(eventId)}'
      : null;
  final senderLink = sender != null
      ? 'https://matrix.to/#/${Uri.encodeComponent(sender)}'
      : null;

  final htmlEscape = HtmlEscape();

  final msgtype = src['msgtype'] as String?;
  final isTextLike = msgtype == 'm.text' || msgtype == 'm.notice';
  final isEmote = msgtype == 'm.emote';
  final isCaptionable = [
    'm.image',
    'm.video',
    'm.audio',
    'm.file',
  ].contains(msgtype);
  final hasCaption =
      isCaptionable &&
      src['filename'] is String &&
      src['filename'] != src['body'];

  final top = jsonDecode(jsonEncode(src)) as Map<String, Object?>;
  for (final key in [
    ..._forwardedContentKeys,
    'm.relates_to',
    'm.mentions',
    'm.new_content',
  ]) {
    top.remove(key);
  }

  var firstLinePlain = sender != null
      ? 'Forwarded from $sender'
      : 'Forwarded message';
  if (permalink != null) {
    firstLinePlain += ' - view original message: $permalink';
  }
  var headerInner = sender != null
      ? 'Forwarded from <a href="$senderLink">${htmlEscape.convert(sender)}</a>'
      : 'Forwarded message';
  if (permalink != null) {
    headerInner += ' - <a href="$permalink">view original message</a>';
  }
  final headerHtml = '<strong>$headerInner</strong>';

  if (isTextLike || isEmote) {
    final bodyText = (src['body'] as String?) ?? '';
    final srcHtml =
        src['format'] == 'org.matrix.custom.html' &&
            src['formatted_body'] is String
        ? src['formatted_body'] as String
        : htmlEscape.convert(bodyText).replaceAll('\n', '<br>');
    final String secondLinePlain;
    final String quotedHtml;
    if (isEmote) {
      top['msgtype'] = 'm.text';
      final actor = senderDisplayName ?? sender ?? 'Sender';
      secondLinePlain = '$actor $bodyText';
      quotedHtml = sender != null
          ? '<em><strong><a href="$senderLink">${htmlEscape.convert(actor)}</a></strong> $srcHtml</em>'
          : '<em><strong>${htmlEscape.convert(actor)}</strong> $srcHtml</em>';
    } else {
      secondLinePlain = bodyText;
      quotedHtml = srcHtml;
    }
    top['body'] = secondLinePlain.isEmpty
        ? firstLinePlain
        : '$firstLinePlain\n$secondLinePlain';
    top['format'] = 'org.matrix.custom.html';
    top['formatted_body'] = quotedHtml.isEmpty
        ? headerHtml
        : '$headerHtml<br><blockquote>$quotedHtml</blockquote>';
  } else if (isCaptionable) {
    top['filename'] = (src['filename'] as String?) ?? src['body'];
    top['body'] = hasCaption
        ? '$firstLinePlain\n${src['body']}'
        : firstLinePlain;
    top['format'] = 'org.matrix.custom.html';
    final captionHtml =
        src['format'] == 'org.matrix.custom.html' &&
            src['formatted_body'] is String
        ? src['formatted_body'] as String
        : htmlEscape
              .convert((src['body'] as String?) ?? '')
              .replaceAll('\n', '<br>');
    top['formatted_body'] = hasCaption
        ? '$headerHtml<br><blockquote>$captionHtml</blockquote>'
        : headerHtml;
  }

  top['m.mentions'] = <String, Object?>{};
  top['org.matrix.msc4553.forwarded'] = forwarded;
  return top;
}

class ShareItem {
  Map<String, Object?>? forwarded;
  ShareItem({this.forwarded});
}

class TextShareItem extends ShareItem {
  final String value;
  TextShareItem(this.value, {super.forwarded});
}

class ContentShareItem extends ShareItem {
  final Map<String, Object?> value;
  final String? eventType;
  ContentShareItem(this.value, {super.forwarded, this.eventType});
}

class FileShareItem extends ShareItem {
  final XFile value;
  FileShareItem(this.value, {super.forwarded});
}

class ShareScaffoldDialog extends StatefulWidget {
  final List<ShareItem> items;

  const ShareScaffoldDialog({required this.items, super.key});

  @override
  State<ShareScaffoldDialog> createState() => _ShareScaffoldDialogState();
}

class _ShareScaffoldDialogState extends State<ShareScaffoldDialog> {
  final TextEditingController _filterController = TextEditingController();

  bool includeAttribution = true;

  String? selectedRoomId;

  void _toggleRoom(String roomId) {
    setState(() {
      selectedRoomId = roomId;
    });
  }

  void _forwardAction() async {
    final roomId = selectedRoomId;
    if (roomId == null) {
      throw Exception(
        'Started forward action before room was selected. This should never happen.',
      );
    }
    while (context.canPop()) {
      context.pop();
    }
    if (!includeAttribution) {
      for (final item in widget.items) {
        item.forwarded = null;
      }
    }
    context.go('/rooms/$roomId', extra: widget.items);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = Matrix.of(context).client.rooms
        .where(
          (room) =>
              room.canSendDefaultMessages &&
              !room.isSpace &&
              room.membership == Membership.join,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          leading: Center(child: CloseButton(onPressed: context.pop)),
          title: Text(L10n.of(context).share),
        ),
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              toolbarHeight: 72,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              title: TextField(
                controller: _filterController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  contentPadding: EdgeInsets.zero,
                  hintText: L10n.of(context).search,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.normal,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: IconButton(
                    onPressed: () {},
                    icon: Icon(
                      Icons.search_outlined,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: rooms.length,
              itemBuilder: (context, i) {
                final room = rooms[i];
                final displayname = room.getLocalizedDisplayname(
                  MatrixLocals(L10n.of(context)),
                );
                final value = selectedRoomId == room.id;
                final filterOut = !displayname.toLowerCase().contains(filter);
                if (!value && filterOut) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Opacity(
                    opacity: filterOut ? 0.5 : 1,
                    child: CheckboxListTile.adaptive(
                      checkboxShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(90),
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                      ),
                      secondary: Avatar(
                        mxContent: room.avatar,
                        name: displayname,
                        size: Avatar.defaultSize * 0.75,
                      ),
                      title: Text(displayname),
                      value: selectedRoomId == room.id,
                      onChanged: (_) => _toggleRoom(room.id),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          child: selectedRoomId == null
              ? const SizedBox.shrink()
              : Material(
                  elevation: 8,
                  shadowColor: theme.appBarTheme.shadowColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: .min,
                      spacing: 4,
                      children: [
                        if (widget.items.any((item) => item.forwarded != null))
                          Row(
                            mainAxisSize: .max,
                            children: [
                              Expanded(
                                child: Text(
                                  L10n.of(context).includeAttribution,
                                ),
                              ),
                              Switch(
                                value: includeAttribution,
                                onChanged: (value) {
                                  setState(() {
                                    includeAttribution = value;
                                  });
                                },
                              ),
                            ],
                          ),
                        Row(
                          mainAxisSize: .max,
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _forwardAction,
                                child: Text(L10n.of(context).forward),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
