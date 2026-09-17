import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/dialer/livekit_call_screen.dart';
import 'package:extera_next/pages/profile/profile_source_data_dialog.dart';
import 'package:extera_next/pages/profile/profile_view.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/localized_exception_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/msc2666_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/user_notes_extension.dart';
import 'package:extera_next/utils/rich_presence.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';

class ProfilePage extends StatefulWidget {
  final Profile profile;
  final bool noProfileWarning;

  const ProfilePage(this.profile, {this.noProfileWarning = false, super.key});

  @override
  State<StatefulWidget> createState() => ProfileController();
}

class ProfileController extends State<ProfilePage> {
  String? about;
  String? tz;
  List<RichPresenceEntry>? richPresences;
  Map<String, dynamic>? profileData;
  Uri? bannerUrl;

  bool isQuerying = false;

  late final TextEditingController noteController;
  Timer? _presenceRefreshTimer;

  void _schedulePresenceRefresh() {
    _presenceRefreshTimer?.cancel();
    final entries = richPresences;
    if (entries == null) return;
    final nearest = RichPresenceEntry.nearestExpiry(entries);
    if (nearest == null) return;
    final delayMs = nearest - DateTime.now().millisecondsSinceEpoch;
    _presenceRefreshTimer = Timer(
      Duration(milliseconds: delayMs < 0 ? 0 : delayMs),
      queryData,
    );
  }

  Future<void> queryData() async {
    final client = Matrix.of(context).client;
    if (isQuerying) return;

    final profile = await client.getUserProfile(
      widget.profile.userId,
      maxCacheAge: const Duration(seconds: 1),
    );
    profileData = profile.toJson();
    if (profile.additionalProperties[AppConfig.aboutProfileField] is String &&
        profile.additionalProperties[AppConfig.aboutProfileField]
                .toString()
                .length <=
            256) {
      setState(() {
        about =
            profile.additionalProperties[AppConfig.aboutProfileField] as String;
      });
    }

    if (profile.mTz != null && profile.mTz!.length <= 256) {
      setState(() {
        tz = profile.mTz;
      });
    }

    if (profile.additionalProperties.containsKey(
          AppConfig.bannerProfileField,
        ) &&
        profile.additionalProperties[AppConfig.bannerProfileField] is String) {
      try {
        final urlString = profile.additionalProperties.tryGet<String>(
          AppConfig.bannerProfileField,
        );
        if (urlString != null) {
          final url = Uri.parse(urlString);
          setState(() {
            bannerUrl = url;
          });
        }
      } catch (e) {
        Logs().e("Failed to parse banner URL", e);
      }
    }

    setState(() {
      richPresences = RichPresenceEntry.parseList(profile.additionalProperties);
    });
    _schedulePresenceRefresh();

    setState(() {
      isQuerying = false;
    });
  }

  List<Room> mutualRooms = [];
  bool canQueryMutualRooms = true;
  bool isQueryingMutualRooms = false;

  Future<void> queryMutualRooms() async {
    final client = Matrix.of(context).client;
    if (!canQueryMutualRooms || isQueryingMutualRooms) return;
    canQueryMutualRooms = await client.isMsc2666Supported();
    setState(() {
      isQueryingMutualRooms = true;
    });
    final rooms = (await client.queryMutualRoomsIds(widget.profile.userId))
        .map((roomId) => client.getRoomById(roomId))
        .where((room) => room != null && !room.isSpace && !room.isDirectChat);
    setState(() {
      mutualRooms = rooms.map((room) => room!).toList();
      isQueryingMutualRooms = false;
    });
  }

  @override
  void initState() {
    final client = Matrix.of(context).client;

    super.initState();
    noteController = TextEditingController(
      text: client.getUserNote(widget.profile.userId) ?? "",
    );
    queryData();

    if (client.userID != widget.profile.userId) {
      queryMutualRooms();
    }
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
    noteController.dispose();
    super.dispose();
  }

  void saveNote(String? note) async {
    note ??= noteController.text;
    await Matrix.of(context).client.setUserNote(widget.profile.userId, note);
  }

  void onChatTap(Room room) {
    if (room.membership == Membership.leave) {
      context.go('/rooms/archive/${room.id}');
      return;
    }

    context.go('/rooms/${room.id}');
  }

  void showProfileData() async {
    if (profileData == null) return;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (context) => ProfileSourceDataDialog(profileData!),
      useRootNavigator: false,
    );
  }

  bool get showCallButton {
    if (!AppSettings.experimentalLiveKit.value) return false;
    final client = Matrix.of(context).client;
    final roomId = client.getDirectChatFromUserId(widget.profile.userId);
    return roomId != null;
  }

  void onCallTap() async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).placeCall,
      message: L10n.of(context).elementCallDescription,
      okLabel: L10n.of(context).continueText,
    );
    if (confirmed != OkCancelResult.ok) return;

    final client = Matrix.of(context).client;
    final roomId = client.getDirectChatFromUserId(widget.profile.userId);
    if (roomId == null) return;
    final room = client.getRoomById(roomId);
    if (room == null) return;
    try {
      await openLiveKitCall(context, roomId);
      context.go('/rooms/$roomId');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      Logs().e("onCallTap", e);
    }
  }

  @override
  Widget build(BuildContext context) => ProfileView(this);
}
