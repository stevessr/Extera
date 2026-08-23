// SPDX-FileCopyrightText: 2026 Extera contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/localized_exception_extension.dart';
import 'package:extera_next/utils/msc/msc_http.dart';
import 'package:extera_next/utils/msc/server_capabilities.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/future_loading_snackbar.dart';

/// Preview of a room based on MSC3266 room summaries, shown before
/// accepting an invitation.
class RoomPreviewPage extends StatefulWidget {
  final Room room;

  const RoomPreviewPage({required this.room, super.key});

  @override
  State<RoomPreviewPage> createState() => _RoomPreviewPageState();
}

class _RoomPreviewPageState extends State<RoomPreviewPage> {
  GetRoomSummaryResponse$3? summary;
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final support = await ServerCapabilityProbe.of(widget.room.client);
      if (!support.roomSummary) {
        if (mounted) {
          setState(() => loading = false);
        }
        return;
      }
      final result = await widget.room.client.getRoomSummary(widget.room.id);
      if (!mounted) return;
      setState(() {
        summary = result;
        loading = false;
      });
    } on MscApiException {
      if (!mounted) return;
      setState(() {
        failed = true;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        failed = true;
        loading = false;
      });
    }
  }

  Future<void> _acceptInvite() async {
    final result = await showFutureLoadingSnackbar(
      context: context,
      future: () async {
        final waitForRoom = widget.room.client.waitForRoomInSync(
          widget.room.id,
          join: true,
        );
        await widget.room.join();
        await waitForRoom;
      },
      exceptionContext: ExceptionContext.joinRoom,
    );
    if (result.isError || !mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _declineInvite() async {
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).decline,
      message: L10n.of(context).areYouSure,
      okLabel: L10n.of(context).yes,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: widget.room.leave,
    );
    if (result.error != null || !mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final room = widget.room;
    final name = summary?.name ?? room.getLocalizedDisplayname();
    final avatar = summary?.avatarUrl ?? room.avatar;
    final memberCount =
        summary?.numJoinedMembers ?? room.summary.mJoinedMemberCount ?? 0;
    final topic = summary?.topic ?? room.topic;
    final encrypted = summary?.encryption != null || room.encrypted;
    final joinRule = summary?.joinRule ?? room.joinRules?.text;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.roomPreview),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.roomSummaryUnavailable,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Center(
            child: Avatar(
              mxContent: avatar,
              name: name,
              size: Avatar.defaultSize * 2,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          finalCanonicalAlias(theme),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.people_alt_outlined, size: 20),
              const SizedBox(width: 8),
              Text('${l10n.roomPreviewMembers}: $memberCount'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (joinRule != null)
                Chip(
                  avatar: Icon(switch (joinRule) {
                    'public' => Icons.lock_open_outlined,
                    'knock' => Icons.doorbell_outlined,
                    _ => Icons.lock_outline,
                  }, size: 18),
                  label: Text(joinRule),
                ),
              Chip(
                avatar: Icon(
                  encrypted
                      ? Icons.enhanced_encryption_outlined
                      : Icons.no_encryption_outlined,
                  size: 18,
                ),
                label: Text(
                  encrypted
                      ? l10n.roomPreviewEncrypted
                      : l10n.roomPreviewNotEncrypted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            topic.isEmpty ? l10n.roomPreviewTopicMissing : topic,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: topic.isEmpty ? theme.colorScheme.outline : null,
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
        ],
      ),
      bottomNavigationBar: room.membership == Membership.invite && !loading
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: Text(l10n.decline),
                        onPressed: _declineInvite,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check_outlined),
                        label: Text(l10n.accept),
                        onPressed: _acceptInvite,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget finalCanonicalAlias(ThemeData theme) {
    final alias = summary?.canonicalAlias;
    if (alias == null || alias.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: Text(
          alias,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
