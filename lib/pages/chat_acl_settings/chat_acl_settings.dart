import 'package:extera_next/pages/chat_acl_settings/chat_acl_settings_view.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ChatAclSettings extends StatefulWidget {
  final String roomId;
  const ChatAclSettings({required this.roomId, super.key});

  @override
  State<StatefulWidget> createState() => ChatAclSettingsController();
}

class ChatAclSettingsController extends State<ChatAclSettings> {
  String get roomId => widget.roomId;

  Room get room => Matrix.of(context).client.getRoomById(roomId)!;

  late bool ipLiteralsDraft;
  late List<String> allowDraft;
  late List<String> denyDraft;
  bool _initialized = false;

  void _ensureDraftsInitialized() {
    if (_initialized) return;
    final serverAcl = room.getState('m.room.server_acl');
    ipLiteralsDraft = serverAcl?.content.tryGet<bool>('allow_ip_literals') ?? false;
    allowDraft =
        (serverAcl?.content['allow'] as List?)
            ?.cast<String>()
            .toList() ??
        ['*'];
    denyDraft =
        (serverAcl?.content['deny'] as List?)
            ?.cast<String>()
            .toList() ??
        [];
    _initialized = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureDraftsInitialized();
  }

  bool get allowIpLiterals => ipLiteralsDraft;

  bool get canEditAcl {
    return room.canChangeStateEvent('m.room.server_acl');
  }

  List<String> get allowServers => allowDraft;
  List<String> get bannedServers => denyDraft;

  void setAllowIpLiterals(bool value) {
    setState(() {
      ipLiteralsDraft = value;
    });
  }

  void addAllowedServer(String server) {
    setState(() {
      allowDraft.add(server);
    });
  }

  void removeAllowedServer(String server) {
    setState(() {
      allowDraft.remove(server);
    });
  }

  void addBannedServer(String server) {
    setState(() {
      denyDraft.add(server);
    });
  }

  void removeBannedServer(String server) {
    setState(() {
      denyDraft.remove(server);
    });
  }

  bool get _userAtRisk {
    final userServer = room.client.userID?.domain;
    if (userServer == null) return false;
    final isAllowed =
        allowDraft.contains('*') || allowDraft.contains(userServer);
    final isDenied =
        denyDraft.contains(userServer) || denyDraft.contains('*');
    return !isAllowed || isDenied;
  }

  void save() async {
    if (_userAtRisk) {
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: 'Warning',
        message:
            'Saving these changes may block you out of the room. Continue?',
        okLabel: 'Save',
        cancelLabel: 'Cancel',
      );
      if (consent != OkCancelResult.ok) return;
    }
    final content = <String, dynamic>{
      'allow_ip_literals': ipLiteralsDraft,
      'deny': denyDraft.toList(),
      'allow': allowDraft.toList(),
    };
    await showFutureLoadingDialog(
      context: context,
      future: () =>
          room.client.setRoomStateWithKey(room.id, 'm.room.server_acl', '', content),
    );
    setState(() {
      _initialized = false;
      _ensureDraftsInitialized();
    });
  }

  @override
  Widget build(BuildContext context) => ChatAclSettingsView(this);
}
