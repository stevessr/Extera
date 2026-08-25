import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'chat_members_view.dart';

class ChatMembersPage extends StatefulWidget {
  final String roomId;

  const ChatMembersPage({required this.roomId, super.key});

  @override
  State<ChatMembersPage> createState() => ChatMembersController();
}

class ChatMembersController extends State<ChatMembersPage> {
  List<User>? members;
  List<User>? filteredMembers;
  Object? error;
  List<User>? _filtersSource;
  List<Membership> _availableFiltersCache = const [];

  /// Membership chips depend only on the raw member list; memoized so
  /// keystroke rebuilds skip the O(membership × members) header scan.
  List<Membership> get availableFilters {
    if (!identical(members, _filtersSource)) {
      _filtersSource = members;
      final filters = Membership.values
          .where(
            (membership) =>
                members?.any((member) => member.membership == membership) ??
                false,
          )
          .toList();
      filters.sort((a, b) => a == Membership.join ? -1 : 1);
      _availableFiltersCache = filters;
    }
    return _availableFiltersCache;
  }

  List<User>? _joinCountSource;
  int _joinedMemberCountCache = 0;

  /// Fallback join count for the chip label when the room summary does
  /// not carry one; recomputed only when the member list changes.
  int get joinedMemberCountFallback {
    if (!identical(members, _joinCountSource)) {
      _joinCountSource = members;
      _joinedMemberCountCache =
          members
              ?.where((member) => member.membership == Membership.join)
              .length ??
          0;
    }
    return _joinedMemberCountCache;
  }

  Membership membershipFilter = Membership.join;
  bool _showIgnoredUsers = false;

  bool get showIgnoredUsers => _showIgnoredUsers;

  void setShowIgnoredUsers(bool value) {
    setState(() {
      _showIgnoredUsers = value;
      setFilter();
    });
  }

  final TextEditingController filterController = TextEditingController();

  void setMembershipFilter(Membership membership) {
    membershipFilter = membership;
    setFilter();
  }

  /// Members are sorted once in [refreshMembers]; filtering preserves
  /// that order so each keystroke only pays a single O(n) pass instead
  /// of a re-sort.
  Future<void> setFilter([_]) async {
    final client = Matrix.of(context).client;
    final filter = filterController.text.toLowerCase().trim();
    final ignoredUsers = client.ignoredUsers;

    setState(() {
      filteredMembers = members
          ?.where((member) => member.membership == membershipFilter)
          .where((user) => showIgnoredUsers || !ignoredUsers.contains(user.id))
          .where(
            (user) =>
                filter.isEmpty ||
                (user.displayName?.toLowerCase().contains(filter) ?? false) ||
                user.id.toLowerCase().contains(filter),
          )
          .toList();
    });
  }

  Future<void> refreshMembers([_]) async {
    Logs().d('Load room members from', widget.roomId);
    try {
      setState(() {
        error = null;
      });
      final participants = await Matrix.of(context).client
          .getRoomById(widget.roomId)
          ?.requestParticipants(
            [...Membership.values]..remove(Membership.leave),
          );

      if (!mounted) return;

      setState(() {
        members = participants
          ?..sort((b, a) => a.powerLevel.level.compareTo(b.powerLevel.level));
        setFilter();
      });
    } catch (e, s) {
      Logs().d(
        'Unable to request participants. Try again in 3 seconds...',
        e,
        s,
      );
      setState(() {
        error = e;
      });
    }
  }

  StreamSubscription? _updateSub;

  @override
  void initState() {
    super.initState();
    refreshMembers();

    _updateSub = Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?[widget.roomId]?.timeline?.events?.any(
                (state) => state.type == EventTypes.RoomMember,
              ) ??
              false,
        )
        .listen(refreshMembers);
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatMembersView(this);
}
