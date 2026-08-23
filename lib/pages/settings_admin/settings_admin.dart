import 'dart:async';

import 'package:flutter/material.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/settings_admin/user_admin_page.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/synapse_admin_extension.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/matrix.dart';

/// Server administration panel (a mobile counterpart of Ketesa /
/// synapse-admin): browse and manage local users and rooms through the
/// Synapse Admin API. Only reachable when the logged-in account is a
/// server admin.
class SettingsAdmin extends StatelessWidget {
  const SettingsAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).serverAdministration),
          bottom: TabBar(
            tabs: [
              Tab(text: L10n.of(context).adminUsersTab),
              Tab(text: L10n.of(context).adminRoomsTab),
            ],
          ),
        ),
        body: const TabBarView(children: [_UsersTab(), _RoomsTab()]),
      ),
    );
  }
}

/// One page of results plus the cursor to fetch the following page.
class _ListPage<T> {
  const _ListPage(this.items, this.next);

  final List<T> items;
  final int? next;
}

class _AdminList<T> extends StatefulWidget {
  const _AdminList({
    required this.loadPage,
    required this.itemBuilder,
    required this.searchHint,
    super.key,
  });

  final Future<_ListPage<T>> Function({
    required String? searchTerm,
    required int from,
  })
  loadPage;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String searchHint;

  @override
  State<_AdminList<T>> createState() => _AdminListState<T>();
}

class _AdminListState<T> extends State<_AdminList<T>> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<T> _items = <T>[];
  int? _next;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Replaces or removes one item after an off-screen detail action
  /// (e.g. editing a user, deleting a room).
  void replaceItem(bool Function(T) test, T? replacement) {
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere(test);
      if (index == -1) return;
      if (replacement == null) {
        _items.removeAt(index);
      } else {
        _items[index] = replacement;
      }
    });
  }

  Future<void> _refresh() async {
    _debounce?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load(from: 0, reset: true);
  }

  Future<void> _loadMore() => _load(from: _next ?? 0, reset: false);

  Future<void> _load({required int from, required bool reset}) async {
    try {
      final page = await widget.loadPage(
        searchTerm: _controller.text.trim().isEmpty
            ? null
            : _controller.text.trim(),
        from: from,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _next = page.next;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _controller,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_outlined),
              hintText: widget.searchHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('$_error'),
                    ),
                  ],
                )
              : _items.isEmpty && !_loading
              ? Center(
                  child: Text(
                    L10n.of(context).adminNoResults,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: _items.length + (_loading ? 1 : 0),
                  itemBuilder: (context, index) => index >= _items.length
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        )
                      : widget.itemBuilder(context, _items[index]),
                ),
        ),
        if (_next != null && !_loading)
          TextButton(
            onPressed: _loadMore,
            child: Text(L10n.of(context).loadMore),
          ),
      ],
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final GlobalKey<_AdminListState<AdminUser>> _listKey =
      GlobalKey<_AdminListState<AdminUser>>();

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return _AdminList<AdminUser>(
      key: _listKey,
      searchHint: L10n.of(context).adminSearchUsers,
      loadPage: ({required String? searchTerm, required int from}) async {
        final page = await client.adminListUsers(
          searchTerm: searchTerm,
          from: from,
        );
        return _ListPage(page.users, page.nextToken);
      },
      itemBuilder: (context, user) => ListTile(
        leading: Avatar(
          mxContent: user.avatarUrl == null
              ? null
              : Uri.tryParse(user.avatarUrl!),
          name: user.effectiveName,
          client: client,
        ),
        title: Text(
          user.effectiveName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.deactivated)
              Icon(
                Icons.block_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            if (user.admin)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
        onTap: () async {
          final updated = await Navigator.of(context).push<AdminUser>(
            MaterialPageRoute(builder: (_) => UserAdminPage(user)),
          );
          if (updated != null) {
            _listKey.currentState?.replaceItem(
              (candidate) => candidate.name == user.name,
              updated,
            );
          }
        },
      ),
    );
  }
}

class _RoomsTab extends StatefulWidget {
  const _RoomsTab();

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  final GlobalKey<_AdminListState<AdminRoomSummary>> _listKey =
      GlobalKey<_AdminListState<AdminRoomSummary>>();

  Future<void> _confirmDelete(AdminRoomSummary room) async {
    var purge = true;
    var block = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(L10n.of(dialogContext).adminDeleteRoom),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.displayName),
              const SizedBox(height: 8),
              Text(L10n.of(dialogContext).adminDeleteRoomWarning),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L10n.of(dialogContext).adminPurgeHistory),
                value: purge,
                onChanged: (value) =>
                    setDialogState(() => purge = value ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L10n.of(dialogContext).adminBlockRoom),
                value: block,
                onChanged: (value) =>
                    setDialogState(() => block = value ?? false),
              ),
            ],
          ),
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
              child: Text(L10n.of(dialogContext).adminDeleteRoom),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    try {
      final kicked = await Matrix.of(
        context,
      ).client.adminDeleteRoom(room.roomId, block: block);
      _listKey.currentState?.replaceItem(
        (candidate) => candidate.roomId == room.roomId,
        null,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminKickedMembers(kicked))),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    return _AdminList<AdminRoomSummary>(
      key: _listKey,
      searchHint: L10n.of(context).adminSearchRooms,
      loadPage: ({required String? searchTerm, required int from}) async {
        final page = await client.adminListRooms(
          searchTerm: searchTerm,
          from: from,
        );
        return _ListPage(page.rooms, page.nextBatch);
      },
      itemBuilder: (context, room) => ListTile(
        leading: Icon(
          room.encrypted ? Icons.lock_outline : Icons.tag_outlined,
          size: 24,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          room.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(
              Icons.people_outline,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(L10n.of(context).adminMemberCount(room.joinedMembers)),
          ],
        ),
        onTap: () => _confirmDelete(room),
      ),
    );
  }
}
