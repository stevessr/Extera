import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/date_time_extension.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/mxc_image.dart';

/// True when the member event switched the avatar of a user, i.e. the
/// `avatar_url` in the content differs from the one in the previous content.
///
/// The SDK already merges `unsigned.prev_content` (synapse style) into
/// [Event.prevContent], so both sources are covered here.
bool isAvatarChangeEvent(Event event) {
  if (event.type != EventTypes.RoomMember) return false;
  final prevContent = event.prevContent;
  if (prevContent == null || prevContent.isEmpty) return false;
  final previousAvatar = prevContent['avatar_url'];
  final currentAvatar = event.content['avatar_url'];
  return previousAvatar != currentAvatar;
}

Uri? _parseAvatar(Object? value) {
  if (value is String && value.startsWith('mxc://')) {
    return Uri.parse(value);
  }
  return null;
}

/// Shows the previous and the new avatar of an avatar change member event.
void showAvatarChangeDialog(BuildContext context, Event event) {
  final prevContent = event.prevContent ?? const <String, dynamic>{};
  final previousAvatar = _parseAvatar(prevContent['avatar_url']);
  final currentAvatar = _parseAvatar(event.content['avatar_url']);
  final name =
      event.stateKeyUser?.calcDisplayname() ?? event.stateKey ?? event.senderId;

  showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(L10n.of(context).avatarChangeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L10n.of(context).changedTheProfileAvatar(name)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AvatarColumn(
                label: L10n.of(context).avatarChangePrevious,
                uri: previousAvatar,
                name: name,
                client: event.room.client,
              ),
              const Icon(Icons.arrow_forward_outlined),
              _AvatarColumn(
                label: L10n.of(context).avatarChangeNew,
                uri: currentAvatar,
                name: name,
                client: event.room.client,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            event.originServerTs.localizedTime(context),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).close),
        ),
      ],
    ),
  );
}

class _AvatarColumn extends StatelessWidget {
  final String label;
  final Uri? uri;
  final String name;
  final Client client;

  const _AvatarColumn({
    required this.label,
    required this.uri,
    required this.name,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(
          mxContent: uri,
          name: name,
          size: 72,
          client: client,
          cacheCategory: MxcImageCacheCategory.userAvatar,
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
