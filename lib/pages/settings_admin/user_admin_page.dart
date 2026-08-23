import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/date_time_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/synapse_admin_extension.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/matrix.dart';

/// Detail editor for a single homeserver account, reached from the admin
/// user list. Supports renaming, toggling the server-admin flag,
/// suspending/reactivating, resetting the password and deactivating
/// (with data erasure) through the Synapse Admin API.
class UserAdminPage extends StatefulWidget {
  const UserAdminPage(this.user, {super.key});

  final AdminUser user;

  @override
  State<UserAdminPage> createState() => _UserAdminPageState();
}

class _UserAdminPageState extends State<UserAdminPage> {
  late final TextEditingController _displaynameController;
  late bool _admin;
  late bool _deactivated;
  AdminUser? _fullUser;

  Client get client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    _displaynameController = TextEditingController(
      text: widget.user.displayname ?? '',
    );
    _admin = widget.user.admin;
    _deactivated = widget.user.deactivated;
    client
        .adminGetUser(widget.user.name)
        .then((user) {
          if (!mounted) return;
          setState(() {
            _fullUser = user;
            if (widget.user.displayname == null && user.displayname != null) {
              _displaynameController.text = user.displayname!;
            }
          });
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _displaynameController.dispose();
    super.dispose();
  }

  Map<String, Object?>? _collectChanges(AdminUser baseline) {
    final changes = <String, Object?>{};
    final displayname = _displaynameController.text.trim();
    final baselineDisplayname = baseline.displayname ?? '';
    if (displayname != baselineDisplayname) {
      changes['displayname'] = displayname;
    }
    if (_admin != baseline.admin) changes['admin'] = _admin;
    if (_deactivated != baseline.deactivated) {
      changes['deactivated'] = _deactivated;
    }
    return changes.isEmpty ? null : changes;
  }

  Future<void> _save() async {
    final baseline = _fullUser ?? widget.user;
    final changes = _collectChanges(baseline);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    if (changes == null) return;
    try {
      await client.adminEditUser(widget.user.name, changes);
      messenger.showSnackBar(SnackBar(content: Text(l10n.adminSaved)));
      if (mounted) {
        Navigator.of(
          context,
        ).pop(AdminUser.fromJson({...baseline.toJson(), ...changes}));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(dialogContext).adminResetPassword),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            hintText: L10n.of(dialogContext).password,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(L10n.of(dialogContext).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(L10n.of(dialogContext).ok),
          ),
        ],
      ),
    );
    if (password == null || password.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    try {
      await client.adminResetPassword(widget.user.name, password);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminResetPasswordDone)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deactivateAndErase() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(dialogContext).adminDeactivateAndErase),
        content: Text(L10n.of(dialogContext).adminDeactivateConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L10n.of(dialogContext).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(L10n.of(dialogContext).ok),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    try {
      await client.adminDeactivateUser(widget.user.name, erase: true);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminDeactivateAndErase)),
      );
      navigator.pop(null);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final full = _fullUser ?? widget.user;
    return Scaffold(
      appBar: AppBar(title: Text(widget.user.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Avatar(
              mxContent: full.avatarUrl == null
                  ? null
                  : Uri.tryParse(full.avatarUrl!),
              name: full.effectiveName,
              size: 72,
              client: client,
            ),
          ),
          const SizedBox(height: 8),
          if (full.creationTs != null)
            Center(
              child: Text(
                l10n.adminCreatedAt(full.creationTs!.localizedTime(context)),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _displaynameController,
            decoration: InputDecoration(
              labelText: l10n.adminDisplayName,
              border: const OutlineInputBorder(),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.shield_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.adminServerAdmin),
            value: _admin,
            onChanged: (value) => setState(() => _admin = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.block_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(l10n.adminDeactivated),
            value: _deactivated,
            onChanged: (value) => setState(() => _deactivated = value),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _resetPassword,
            icon: const Icon(Icons.password_outlined),
            label: Text(l10n.adminResetPassword),
          ),
          const Divider(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.adminSave),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.adminDangerZone,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _deactivateAndErase,
            icon: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            label: Text(
              l10n.adminDeactivateAndErase,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
