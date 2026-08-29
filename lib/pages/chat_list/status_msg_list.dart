import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/interesting_presences_extension.dart';
import 'package:extera_next/utils/show_profile.dart';
import 'package:extera_next/utils/stream_extension.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/hover_builder.dart';
import 'package:extera_next/widgets/matrix.dart';

class StatusMessageList extends StatefulWidget {
  final void Function() onStatusEdit;

  const StatusMessageList({required this.onStatusEdit, super.key});

  static const double height = 116;

  @override
  State<StatusMessageList> createState() => _StatusMessageListState();
}

class _StatusMessageListState extends State<StatusMessageList> {
  Client? _boundClient;
  Stream<bool>? _syncStream;

  Set<String> _presenceKey = const {};
  Future<List<CachedPresence>> _presenceFuture = Future.value(const []);

  /// Returns a stable rate-limited sync stream per client instead of
  /// composing a fresh pipeline per build: recreating it would make the
  /// StreamBuilder unsubscribe/resubscribe and reset the rate-limit window
  /// on every parent rebuild.
  Stream<bool> _getSyncStream(Client client) {
    if (!identical(client, _boundClient)) {
      _boundClient = client;
      _syncStream = client.onSync.stream.rateLimit(const Duration(seconds: 3));
    }
    return _syncStream!;
  }

  /// Presence lookups are memoized until the set of interesting users
  /// changes, so rebuilds reuse the in-flight/completed future instead of
  /// refiring a lookup per user on every rebuild.
  Future<List<CachedPresence>> _getPresenceFuture(Client client) {
    final users = client.interestingPresences;
    if (identical(client, _boundClient) && setEquals(users, _presenceKey)) {
      return _presenceFuture;
    }
    _boundClient = client;
    _presenceKey = Set<String>.of(users);
    return _presenceFuture = Future.wait(
      users.map(
        (userId) =>
            client.fetchCurrentPresence(userId, fetchOnlyFromCached: true),
      ),
    );
  }

  void _onStatusTab(BuildContext context, Profile profile) {
    final client = Matrix.of(context).client;
    if (profile.userId == client.userID) return widget.onStatusEdit();

    showProfile(context: context, profile: profile);
    return;
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;

    return StreamBuilder(
      stream: _getSyncStream(client),
      builder: (context, snapshot) {
        return AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: Curves.easeInOut,
          child: FutureBuilder<List<CachedPresence>>(
            future: _getPresenceFuture(client),
            builder: (context, snapshot) {
              final presences = snapshot.data
                  ?.where(isInterestingPresence)
                  .toList();

              // If no other presences than the own entry is interesting, we
              // hide the presence header.
              if (presences == null || presences.length <= 1) {
                return const SizedBox.shrink();
              }

              // Make sure own entry is at the first position. Sort by last
              // active instead.
              presences.sort((a, b) {
                if (a.userid == client.userID) return -1;
                if (b.userid == client.userID) return 1;
                return b.sortOrderDateTime.compareTo(a.sortOrderDateTime);
              });

              return SizedBox(
                height: StatusMessageList.height,
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  scrollDirection: Axis.horizontal,
                  itemCount: presences.length,
                  itemBuilder: (context, i) => PresenceAvatar(
                    presence: presences[i],
                    height: StatusMessageList.height,
                    onTap: (profile) => _onStatusTab(context, profile),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Memoized profile lookups for presence avatars: the underlying SDK call
/// hits the database cache on every invocation, which used to happen once
/// per visible avatar on every list rebuild. Failed lookups evict
/// themselves so they are retried.
final Map<String, Future<Profile>> _presenceProfileCache = {};

Future<Profile> _getProfileCached(Client client, String userId) {
  final cached = _presenceProfileCache[userId];
  if (cached != null) return cached;
  final future = client.getProfileFromUserId(userId).catchError((Object error) {
    _presenceProfileCache.remove(userId);
    throw error;
  });
  if (_presenceProfileCache.length > 128) {
    _presenceProfileCache.remove(_presenceProfileCache.keys.first);
  }
  return _presenceProfileCache[userId] = future;
}

class PresenceAvatar extends StatelessWidget {
  final CachedPresence presence;
  final double height;
  final void Function(Profile) onTap;

  const PresenceAvatar({
    required this.presence,
    required this.height,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = height - 16 - 16 - 8;
    final client = Matrix.of(context).client;
    return FutureBuilder<Profile>(
      future: _getProfileCached(client, presence.userid),
      builder: (context, snapshot) {
        final theme = Theme.of(context);

        final profile = snapshot.data;
        final displayName =
            profile?.displayName ??
            presence.userid.localpart ??
            presence.userid;
        final statusMsg = presence.statusMsg;

        const statusMsgBubbleElevation = 6.0;
        final statusMsgBubbleShadowColor = theme.colorScheme.surfaceBright;
        final statusMsgBubbleColor = Colors.white.withAlpha(212);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: SizedBox(
            width: avatarSize,
            child: Column(
              children: [
                HoverBuilder(
                  builder: (context, hovered) {
                    return AnimatedScale(
                      scale: hovered ? 1.15 : 1.0,
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          avatarSize * AppSettings.avatarBorderRadius.value,
                        ),
                        onTap: profile == null ? null : () => onTap(profile),
                        child: Material(
                          borderRadius: BorderRadius.circular(
                            avatarSize * AppSettings.avatarBorderRadius.value,
                          ),
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  gradient: presence.gradient,
                                  borderRadius: BorderRadius.circular(
                                    avatarSize *
                                        AppSettings.avatarBorderRadius.value *
                                        0.5,
                                  ),
                                ),
                                child: Avatar(
                                  name: displayName,
                                  mxContent: profile?.avatarUrl,
                                  size: avatarSize - 6,
                                ),
                              ),
                              if (presence.userid == client.userID)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: FloatingActionButton.small(
                                      heroTag: null,
                                      onPressed: () => onTap(
                                        profile ??
                                            Profile(userId: presence.userid),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.add_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              if (statusMsg != null) ...[
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  right: 8,
                                  child: Material(
                                    elevation: statusMsgBubbleElevation,
                                    shadowColor: statusMsgBubbleShadowColor,
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius / 2,
                                    ),
                                    color: statusMsgBubbleColor,
                                    child: Padding(
                                      padding: const EdgeInsets.all(2.0),
                                      child: Text(
                                        statusMsg,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  top: 32,
                                  child: Material(
                                    color: statusMsgBubbleColor,
                                    elevation: statusMsgBubbleElevation,
                                    shadowColor: statusMsgBubbleShadowColor,
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius / 2,
                                    ),
                                    child: const SizedBox(width: 8, height: 8),
                                  ),
                                ),
                                Positioned(
                                  left: 14,
                                  top: 40,
                                  child: Material(
                                    color: statusMsgBubbleColor,
                                    elevation: statusMsgBubbleElevation,
                                    shadowColor: statusMsgBubbleShadowColor,
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius / 2,
                                    ),
                                    child: const SizedBox(width: 4, height: 4),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
