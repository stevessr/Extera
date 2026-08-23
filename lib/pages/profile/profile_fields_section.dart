// SPDX-FileCopyrightText: 2026 Extera contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/msc/server_capabilities.dart';
import 'package:extera_next/pages/profile/profile.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/list_divider.dart';

/// Manage arbitrary MSC4133 extended profile fields of the own user.
/// Renders nothing if the homeserver lacks the `m.profile_fields`
/// capability or the page shows another user's profile.
class ProfileFieldsSection extends StatefulWidget {
  final ProfileController controller;

  const ProfileFieldsSection(this.controller, {super.key});

  @override
  State<ProfileFieldsSection> createState() => _ProfileFieldsSectionState();
}

class _ProfileFieldsSectionState extends State<ProfileFieldsSection> {
  ServerMscSupport? support;
  Map<String, Object?> fields = {};
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final client = Matrix.of(context).client;
    try {
      final probed = await ServerCapabilityProbe.of(client);
      if (!probed.customProfileFields || !mounted) {
        if (mounted) {
          setState(() {
            support = probed;
            loading = false;
          });
        }
        return;
      }
      final profile = await client.getUserProfile(
        widget.controller.widget.profile.userId,
        maxCacheAge: const Duration(seconds: 1),
      );
      if (!mounted) return;
      setState(() {
        support = probed;
        fields = profile.additionalProperties;
        failed = false;
        loading = false;
      });
    } catch (e) {
      Logs().d('Loading custom profile fields failed', e);
      if (!mounted) return;
      setState(() {
        failed = true;
        loading = false;
      });
    }
  }

  Future<void> _saveField(String key, String valueText) async {
    final client = Matrix.of(context).client;
    Object? value = valueText;
    try {
      value = jsonDecode(valueText);
    } catch (_) {
      // Plain string value.
    }
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.setProfileField(client.userID!, key, {key: value}),
    );
    if (result.isError || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.of(context).profileFieldSaved)));
    await _reload();
  }

  Future<void> _deleteField(String key) async {
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).deleteCustomProfileField,
      message: key,
      okLabel: L10n.of(context).yes,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.deleteProfileField(client.userID!, key),
    );
    if (result.isError || !mounted) return;
    await _reload();
  }

  /// The stable MSC4133 grammar requires namespaced custom field keys
  /// like `com.example.job_title`.
  static final RegExp _namespacedKey = RegExp(
    r'^[a-z0-9_\-]+(\.[a-z0-9_\-./]+)+$',
    caseSensitive: false,
  );

  Future<void> _showEditDialog({String? existingKey}) async {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final support = this.support;
    if (support == null) return;
    final keyController = TextEditingController(text: existingKey);
    final valueText = fields[existingKey];
    final valueController = TextEditingController(
      text: valueText == null
          ? ''
          : valueText is String
          ? valueText
          : jsonEncode(valueText),
    );
    final formKey = GlobalKey<FormState>();
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existingKey ?? l10n.addCustomProfileField),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: keyController,
                  enabled: existingKey == null,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.customProfileFieldName,
                    hintText: 'com.example.title',
                    errorText: errorText,
                  ),
                  validator: (value) {
                    final key = value?.trim() ?? '';
                    if (key.isEmpty) {
                      return l10n.invalidProfileFieldName;
                    }
                    if (!_namespacedKey.hasMatch(key) &&
                        !(support.canSetProfileField(key))) {
                      return l10n.invalidProfileFieldName;
                    }
                    if (!support.canSetProfileField(key)) {
                      return l10n.invalidProfileFieldName;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: valueController,
                  autocorrect: false,
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: l10n.customProfileFieldValue,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(context).pop(true);
              },
              child: Text(existingKey ?? l10n.addCustomProfileField),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final key = keyController.text.trim();
    if (key.isNotEmpty) {
      await _saveField(key, valueController.text);
    }
  }

  String _stringify(Object? value) {
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    if (loading && support?.customProfileFields != true) {
      // Optimistically render nothing until the probe resolves; avoids
      // flicker for servers without support.
      return const SizedBox.shrink();
    }
    final editableKeys = fields.keys.toList()..sort();
    return Material(
      clipBehavior: Clip.hardEdge,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          ListTile(
            title: Text(
              l10n.customProfileFields,
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing:
                support?.customProfileFields == true &&
                    widget.controller.widget.profile.userId ==
                        Matrix.of(context).client.userID
                ? IconButton(
                    tooltip: l10n.addCustomProfileField,
                    icon: const Icon(Icons.add_outlined),
                    onPressed: _showEditDialog,
                  )
                : null,
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.roomSummaryUnavailable,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (!failed)
            for (var i = 0; i < editableKeys.length; i++) ...[
              if (i > 0) const ListDivider(),
              ListTile(
                title: Text(
                  editableKeys[i],
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: Text(
                  _stringify(fields[editableKeys[i]]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _showEditDialog(existingKey: editableKeys[i]),
                trailing: IconButton(
                  tooltip: l10n.deleteCustomProfileField,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteField(editableKeys[i]),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
