import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/matrix.dart';

import 'settings_custom_experience_view.dart';

const String _roomPrivacySettingsPrefix = 'xyz.extera.room_privacy_settings.';

class SettingsCustomExperience extends StatefulWidget {
  const SettingsCustomExperience({super.key});

  @override
  SettingsCustomExperienceController createState() =>
      SettingsCustomExperienceController();
}

class SettingsCustomExperienceController
    extends State<SettingsCustomExperience> {
  Future<List<Room>> _customizedRooms = Future.value(const []);

  /// Chats in which the user applied at least one of the per-chat
  /// customizations: an own wallpaper, privacy settings or a profile that
  /// differs from the account profile. Recomputed after visiting a room's
  /// customization screen, see [openRoom].
  Future<List<Room>> get customizedRooms => _customizedRooms;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _customizedRooms = _loadCustomizedRooms();
    });
  }

  Future<List<Room>> _loadCustomizedRooms() async {
    final client = Matrix.of(context).client;
    final profile = await client.fetchOwnProfile();
    return client.rooms
        .where((room) => room.membership == Membership.join)
        .where((room) => _isCustomized(client, room, profile))
        .toList();
  }

  bool _isCustomized(Client client, Room room, Profile profile) {
    if (hasRoomWallpaper(room.id)) return true;
    final privacyContent =
        client.accountData['$_roomPrivacySettingsPrefix${room.id}']?.content;
    if (privacyContent != null && privacyContent.isNotEmpty) return true;
    final memberContent = room
        .getState(EventTypes.RoomMember, client.userID!)
        ?.content;
    final displayname = memberContent?['displayname'] as String?;
    if (displayname != null && displayname != profile.displayName) return true;
    final avatarUrl = memberContent?['avatar_url'] as String?;
    if (avatarUrl != null && avatarUrl != profile.avatarUrl?.toString()) {
      return true;
    }
    return false;
  }

  void openRoom(BuildContext context, Room room) async {
    await context.push('/rooms/${room.id}/details/custom_experience');
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => SettingsCustomExperienceView(this);
}
