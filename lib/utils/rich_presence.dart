/// Model + parser for MSC4544 rich presence viewing.
///
/// The profile field `xyz.extera.msc4544.rpc` contains a JSON array of
/// presence entries. This file parses and validates those entries and drops
/// expired or malformed ones. It intentionally covers viewing only.
library;

enum RichPresenceType { activity, music }

class RichPresenceButton {
  final String label;
  final String url;
  final bool requestOpenid;

  const RichPresenceButton({
    required this.label,
    required this.url,
    required this.requestOpenid,
  });
}

class RichPresenceEntry {
  static const String profileField = 'xyz.extera.msc4544.rpc';
  static const String activityType = 'xyz.extera.msc4544.rpc.activity';
  static const String musicType = 'xyz.extera.msc4544.rpc.music';

  final RichPresenceType type;

  /// Epoch milliseconds; null = no expiry.
  final int? expiry;

  // Activity fields
  final String? name;
  final String? state;
  final String? details;
  final int? since;
  final int? until;
  final Uri? largeIconUrl;
  final Uri? smallIconUrl;
  final String? largeIconTooltip;
  final String? smallIconTooltip;

  // Music fields
  final String? track;
  final String? artist;
  final String? album;
  final String? playerName;
  final Uri? coverUrl;
  final int? progressSince;
  final int? progressUntil;

  // Common
  final List<RichPresenceButton> buttons;

  const RichPresenceEntry._({
    required this.type,
    this.expiry,
    this.name,
    this.state,
    this.details,
    this.since,
    this.until,
    this.largeIconUrl,
    this.smallIconUrl,
    this.largeIconTooltip,
    this.smallIconTooltip,
    this.track,
    this.artist,
    this.album,
    this.playerName,
    this.coverUrl,
    this.progressSince,
    this.progressUntil,
    this.buttons = const [],
  });

  /// Parses the `xyz.extera.msc4544.rpc` field from profile
  /// additionalProperties. Returns validated, non-expired entries. Empty list
  /// if field absent/invalid.
  static List<RichPresenceEntry> parseList(
    Map<String, Object?>? additionalProperties,
  ) {
    final rawList = additionalProperties?[profileField];
    if (rawList is! List) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <RichPresenceEntry>[];
    for (final element in rawList) {
      if (element is! Map) continue;
      final entry = _parseEntry(element, now);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// Minimum non-null expiry among entries, or null if none.
  static int? nearestExpiry(List<RichPresenceEntry> entries) {
    int? nearest;
    for (final entry in entries) {
      final expiry = entry.expiry;
      if (expiry == null) continue;
      if (nearest == null || expiry < nearest) nearest = expiry;
    }
    return nearest;
  }

  static RichPresenceEntry? _parseEntry(
    Map<Object?, Object?> element,
    int now,
  ) {
    final typeString = _asString(element['type']);
    final RichPresenceType type;
    switch (typeString) {
      case activityType:
        type = RichPresenceType.activity;
      case musicType:
        type = RichPresenceType.music;
      default:
        return null;
    }

    final expiry = _asEpochMs(element['expiry']);
    if (expiry != null && expiry <= now) return null;

    final buttons = _parseButtons(element['buttons']);

    switch (type) {
      case RichPresenceType.activity:
        final name = _asString(element['name']);
        if (name == null) return null;
        final largeIconUrl = _asMxcUri(element['large_icon_url']);
        final smallIconUrl = largeIconUrl == null
            ? null
            : _asMxcUri(element['small_icon_url']);
        return RichPresenceEntry._(
          type: type,
          expiry: expiry,
          name: name,
          state: _asString(element['state']),
          details: _asString(element['details']),
          since: _asEpochMs(element['since']),
          until: _asEpochMs(element['until']),
          largeIconUrl: largeIconUrl,
          smallIconUrl: smallIconUrl,
          largeIconTooltip: largeIconUrl == null
              ? null
              : _asString(element['large_icon_tooltip']),
          smallIconTooltip: smallIconUrl == null
              ? null
              : _asString(element['small_icon_tooltip']),
          buttons: buttons,
        );
      case RichPresenceType.music:
        final track = _asString(element['track']);
        if (track == null) return null;
        final progressSinceUntil = _parseProgress(element['progress']);
        return RichPresenceEntry._(
          type: type,
          expiry: expiry,
          track: track,
          artist: _asString(element['artist']),
          album: _asString(element['album']),
          playerName: _asString(element['player_name']),
          coverUrl: _asMxcUri(element['cover_url']),
          progressSince: progressSinceUntil.$1,
          progressUntil: progressSinceUntil.$2,
          buttons: buttons,
        );
    }
  }

  /// Progress must contain both `since` and `until` as epoch ms or be absent
  /// entirely. Returns (since, until) or (null, null) if malformed.
  static (int?, int?) _parseProgress(Object? progress) {
    if (progress is! Map) return (null, null);
    final since = _asEpochMs(progress['since']);
    final until = _asEpochMs(progress['until']);
    if (since == null || until == null) return (null, null);
    return (since, until);
  }

  static List<RichPresenceButton> _parseButtons(Object? rawButtons) {
    if (rawButtons is! List) return const [];
    final buttons = <RichPresenceButton>[];
    for (final element in rawButtons) {
      if (buttons.length >= 3) break;
      if (element is! Map) continue;
      final label = _asString(element['label']);
      final url = _asString(element['url']);
      if (label == null || url == null) continue;
      buttons.add(
        RichPresenceButton(
          label: label,
          url: url,
          requestOpenid: element['request_openid'] == true,
        ),
      );
    }
    return buttons;
  }
}

String? _asString(Object? value) => value is String ? value : null;

int? _asEpochMs(Object? value) =>
    value is int ? value : (value is num ? value.toInt() : null);

Uri? _asMxcUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'mxc') return null;
  return uri;
}
