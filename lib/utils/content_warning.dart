import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';

/// Content warnings as proposed by MSC3725.
///
/// The event carries the warning twice: once as the MSC3725 object that says
/// *why* the content is hidden, and once as the MSC4193 boolean that clients
/// without MSC3725 support use to blur it anyway.
const String contentWarningKey = 'town.robin.msc3725.content_warning';
const String contentWarningSpoilerKey =
    'page.codeberg.everypizza.msc4193.spoiler';

enum ContentWarningType {
  spoiler('town.robin.msc3725.spoiler'),
  nsfw('town.robin.msc3725.nsfw'),
  graphic('town.robin.msc3725.graphic'),
  medical('town.robin.msc3725.medical');

  /// The value stored in the event.
  final String value;

  const ContentWarningType(this.value);

  String label(L10n l10n) => switch (this) {
    ContentWarningType.spoiler => l10n.contentWarningSpoiler,
    ContentWarningType.nsfw => l10n.contentWarningNsfw,
    ContentWarningType.graphic => l10n.contentWarningGraphic,
    ContentWarningType.medical => l10n.contentWarningMedical,
  };
}

/// The content warning of an event, or `null` when it has none.
///
/// The raw value is returned rather than a [ContentWarningType], because other
/// clients may set a type this one does not know about, and dropping it while
/// editing would silently unhide the content.
String? contentWarningOf(Map<String, dynamic> content) => content
    .tryGetMap<String, Object?>(contentWarningKey)
    ?.tryGet<String>('type');

/// Localized name of [type], falling back to the generic wording for values
/// this client does not know.
String contentWarningLabel(L10n l10n, String? type) {
  if (type == null) return l10n.none;
  for (final known in ContentWarningType.values) {
    if (known.value == type) return known.label(l10n);
  }
  return l10n.contentWarning;
}

/// Writes [type] into [content], removing the warning when it is `null`.
void applyContentWarning(Map<String, dynamic> content, String? type) {
  if (type == null) {
    content.remove(contentWarningKey);
    content.remove(contentWarningSpoilerKey);
    return;
  }
  content[contentWarningKey] = {'type': type};
  content[contentWarningSpoilerKey] = true;
}
