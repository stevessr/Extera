// SPDX-FileCopyrightText: 2026 Extera contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/msc/msc_http.dart';

/// Which of the MSC features this app uses are available on the homeserver.
///
/// - Room summaries (MSC3266) are stable since spec v1.15 and probed
///   optimistically; callers must handle failures gracefully.
/// - Custom profile fields (MSC4133) are stable since spec v1.16 and read
///   from the `m.profile_fields` capability.
/// - Delayed events (MSC4140) are still experimental everywhere (Synapse
///   requires `max_event_delay_duration` to be set) and are detected by
///   probing the management endpoint.
class ServerMscSupport {
  final bool roomSummary;
  final bool customProfileFields;

  /// If non-null, only these profile fields may be written.
  final List<String>? allowedProfileFields;

  /// Only meaningful if [allowedProfileFields] is null.
  final List<String>? disallowedProfileFields;
  final bool delayedEvents;

  const ServerMscSupport({
    required this.roomSummary,
    required this.customProfileFields,
    this.allowedProfileFields,
    this.disallowedProfileFields,
    required this.delayedEvents,
  });

  static const unsupported = ServerMscSupport(
    roomSummary: false,
    customProfileFields: false,
    delayedEvents: false,
  );

  /// May the user write the given profile field?
  bool canSetProfileField(String keyName) {
    if (!customProfileFields) return false;
    final allowed = allowedProfileFields;
    if (allowed != null) return allowed.contains(keyName);
    return !(disallowedProfileFields?.contains(keyName) ?? false);
  }
}

class ServerCapabilityProbe {
  static final Map<String, Future<ServerMscSupport>> _cache = {};

  /// Probed once per client session, keyed by user ID.
  static Future<ServerMscSupport> of(Client client) {
    final key = client.userID ?? '';
    if (key.isEmpty) {
      return Future.value(ServerMscSupport.unsupported);
    }
    return _cache.putIfAbsent(key, () => _probe(client));
  }

  /// Drop a cached result (e.g. after account switch or on failure).
  static void invalidate(Client client) =>
      _cache.remove(client.userID ?? '');

  static Future<ServerMscSupport> _probe(Client client) async {
    try {
      final versions = await client.getVersions();
      final unstable = versions.unstableFeatures ?? const {};
      final specVersions = versions.versions;

      // MSC3266: stable in v1.15. Trust the advertised spec version and
      // fall back to optimistic true for servers not advertising versions
      // (callers must still handle errors gracefully).
      final roomSummary =
          specVersions.isEmpty || _specAtLeast(specVersions, 'v1.15');

      var customProfileFields = false;
      List<String>? allowed;
      List<String>? disallowed;
      try {
        final capabilities = await client.getCapabilities();
        final profileFields = capabilities.mProfileFields;
        customProfileFields = profileFields?.enabled ?? false;
        allowed = profileFields?.allowed;
        disallowed = profileFields?.disallowed;
      } catch (_) {
        // Older servers without /capabilities or without the capability:
        // no custom profile field support.
      }

      var delayedEvents = false;
      // Positive hints only: some servers advertise unstable features.
      final hintedDelayed =
          unstable['org.matrix.msc4140'] == true ||
              unstable['msc4140'] == true;
      if (hintedDelayed) {
        delayedEvents = true;
      } else {
        // Probe: a server without MSC4140 answers 404 M_UNRECOGNIZED /
        // M_UNKNOWN; one with support answers 200 with an empty list.
        try {
          await MscHttp(client).getJson(
            '_matrix/client/unstable/org.matrix.msc4140/delayed_events',
          );
          delayedEvents = true;
        } on MscApiException catch (e) {
          if (!e.unrecognized) {
            // Rate limited or other transient error: assume supported so
            // the UI does not silently hide the feature forever.
            Logs().d('MSC4140 probe failed', e);
            delayedEvents = e.statusCode == 429;
          }
        } catch (e) {
          Logs().d('MSC4140 probe failed', e);
        }
      }

      return ServerMscSupport(
        roomSummary: roomSummary,
        customProfileFields: customProfileFields,
        allowedProfileFields: allowed,
        disallowedProfileFields: disallowed,
        delayedEvents: delayedEvents,
      );
    } catch (e, s) {
      Logs().d('MSC capability probe failed', e, s);
      return ServerMscSupport.unsupported;
    }
  }

  static bool _specAtLeast(List<String> versions, String minimum) {
    int parse(String v) => int.tryParse(v.split('.').last) ?? 0;
    final minMinor = parse(minimum);
    for (final v in versions) {
      final match = RegExp(r'^v1\.(\d+)$').firstMatch(v);
      if (match != null && int.parse(match.group(1)!) >= minMinor) {
        return true;
      }
    }
    return false;
  }
}
