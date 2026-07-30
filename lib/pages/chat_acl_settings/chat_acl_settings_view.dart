import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/pages/chat_acl_settings/chat_acl_settings.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:flutter/material.dart';

class ChatAclSettingsView extends StatelessWidget {
  final ChatAclSettingsController controller;
  const ChatAclSettingsView(this.controller, {super.key});

  Future<void> _addServer(BuildContext context, {required bool allowed}) async {
    final input = await showTextInputDialog(
      context: context,
      title: allowed ? 'Add allowed server' : 'Add banned server',
      message: 'Enter the server hostname (e.g. example.org)',
      hintText: 'example.org',
      okLabel: 'Add',
      cancelLabel: 'Cancel',
    );
    final server = input?.trim();
    if (server == null || server.isEmpty) return;
    if (allowed) {
      controller.addAllowedServer(server);
    } else {
      controller.addBannedServer(server);
    }
  }

  Widget _buildServerName(BuildContext context, String name) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: borderRadius,
      clipBehavior: .hardEdge,
      child: Padding(
        padding: const .symmetric(horizontal: 16, vertical: 10),
        child: Text(
          name,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontFamily: AppSettings.monospaceFont.value,
            fontFamilyFallback: AppSettings.monospaceFallbackFonts.value.split(
              ',',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);
    final canEdit = controller.canEditAcl;

    return Scaffold(
      appBar: AppBar(
        title: Text('ACL settings'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
              onPressed: controller.save,
            ),
        ],
      ),
      body: MaxWidthBody(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  borderRadius: borderRadius,
                  color: theme.colorScheme.surfaceContainerHigh,
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        secondary: CircleAvatar(
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: const Icon(Icons.numbers),
                        ),
                        title: Text('Allow IP literals'),
                        value: controller.allowIpLiterals,
                        onChanged: canEdit
                            ? controller.setAllowIpLiterals
                            : null,
                      ),
                      const ListDivider(),
                      ListTile(
                        leading: CircleAvatar(
                          foregroundColor:
                              theme.colorScheme.onTertiaryContainer,
                          backgroundColor: theme.colorScheme.tertiaryContainer,
                          child: const Icon(Icons.check_circle_outline),
                        ),
                        title: Text('Allowed servers'),
                        trailing: canEdit
                            ? IconButton(
                                icon: const Icon(Icons.add_outlined),
                                tooltip: 'Add allowed server',
                                onPressed: () =>
                                    _addServer(context, allowed: true),
                              )
                            : null,
                      ),
                      for (final server in controller.allowServers)
                        ListTile(
                          title: _buildServerName(context, server),
                          dense: true,
                          trailing: canEdit
                              ? IconButton(
                                  color: theme.colorScheme.error,
                                  icon: const Icon(Icons.delete_outlined),
                                  onPressed: () =>
                                      controller.removeAllowedServer(server),
                                )
                              : null,
                        ),
                      const ListDivider(),
                      ListTile(
                        leading: CircleAvatar(
                          foregroundColor: theme.colorScheme.onErrorContainer,
                          backgroundColor: theme.colorScheme.errorContainer,
                          child: const Icon(Icons.block_outlined),
                        ),
                        title: Text('Banned servers'),
                        trailing: canEdit
                            ? IconButton(
                                icon: const Icon(Icons.add_outlined),
                                tooltip: 'Add banned server',
                                onPressed: () =>
                                    _addServer(context, allowed: false),
                              )
                            : null,
                      ),
                      for (final server in controller.bannedServers)
                        ListTile(
                          title: _buildServerName(context, server),
                          dense: true,
                          trailing: canEdit
                              ? IconButton(
                                  color: theme.colorScheme.error,
                                  icon: const Icon(Icons.delete_outlined),
                                  onPressed: () =>
                                      controller.removeBannedServer(server),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
