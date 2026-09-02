import 'package:extera_next/utils/emote_shortcode.dart';

const legacyRoomImagePackEventType = 'im.ponies.room_emotes';
const legacyUserImagePackEventType = 'im.ponies.user_emotes';
const legacyImagePackRoomsEventType = 'im.ponies.emote_rooms';

const _stableImagePackUsages = <String>{'emoticon', 'sticker'};

/// Converts an MSC2545-era image pack to the stable `m.room.image_pack`
/// shape without losing images.
///
/// The old `im.ponies.*` proposal allowed `usage` on individual images while
/// stable MSC2545 only defines it on the pack. If a legacy pack used
/// per-image values, keep the union of those usages at pack level. A legacy
/// image without an explicit usage means "all usages", so in that case the
/// stable pack also remains unrestricted.
///
/// Historical Extera versions also allowed shortcodes outside the stable
/// MSC2545 grammar. Stable writes normalize those keys to ASCII/100 bytes and
/// resolve collisions deterministically. When a key changes, its original
/// value is retained as the image `body` if the pack did not already provide
/// one, so migration keeps the human-readable name as well as the image.
Map<String, dynamic> normalizeStableImagePackContent(
  Map<String, dynamic> source,
) {
  final content = Map<String, dynamic>.from(source);

  final rawPack = content['pack'];
  final pack = rawPack is Map
      ? Map<String, dynamic>.from(rawPack)
      : <String, dynamic>{};
  final hasExplicitPackUsage = pack.containsKey('usage');
  final packUsage = _readUsage(pack['usage']);

  final rawImages = content['images'];
  final images = <String, dynamic>{};
  final usedShortcodes = <String>{};
  final inferredUsage = <String>{};
  var hasUnrestrictedImage = false;

  if (rawImages is Map) {
    for (final entry in rawImages.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final originalShortcode = entry.key as String;
      final stableShortcode = uniqueEmoteShortcode(
        originalShortcode,
        usedShortcodes,
      );
      final image = Map<String, dynamic>.from(entry.value as Map);
      final imageUsage = _readUsage(image.remove('usage'));

      if (stableShortcode != originalShortcode && !image.containsKey('body')) {
        image['body'] = originalShortcode;
      }

      if (!hasExplicitPackUsage) {
        if (imageUsage == null || imageUsage.isEmpty) {
          hasUnrestrictedImage = true;
        } else {
          inferredUsage.addAll(imageUsage);
        }
      }

      images[stableShortcode] = image;
    }
  }

  if (!hasExplicitPackUsage &&
      !hasUnrestrictedImage &&
      inferredUsage.isNotEmpty) {
    pack['usage'] = [
      if (inferredUsage.contains('emoticon')) 'emoticon',
      if (inferredUsage.contains('sticker')) 'sticker',
    ];
  } else if (hasExplicitPackUsage && packUsage != null) {
    // Keep stable values deterministic and discard unknown legacy values.
    pack['usage'] = [
      if (packUsage.contains('emoticon')) 'emoticon',
      if (packUsage.contains('sticker')) 'sticker',
    ];
  }

  content['images'] = images;
  if (rawPack != null || pack.isNotEmpty) {
    content['pack'] = pack;
  }
  return content;
}

Set<String>? _readUsage(Object? raw) {
  if (raw is! Iterable) return null;
  return raw.whereType<String>().where(_stableImagePackUsages.contains).toSet();
}
