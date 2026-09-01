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
Map<String, dynamic> normalizeStableImagePackContent(
  Map<String, dynamic> source,
) {
  final content = Map<String, dynamic>.from(source);

  final rawPack = content['pack'];
  final pack = rawPack is Map
      ? Map<String, dynamic>.from(rawPack)
      : <String, dynamic>{};
  final packUsage = _readUsage(pack['usage']);

  final rawImages = content['images'];
  final images = <String, dynamic>{};
  final inferredUsage = <String>{};
  var hasUnrestrictedImage = false;

  if (rawImages is Map) {
    for (final entry in rawImages.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final image = Map<String, dynamic>.from(entry.value as Map);
      final imageUsage = _readUsage(image.remove('usage'));

      if (packUsage == null || packUsage.isEmpty) {
        if (imageUsage == null || imageUsage.isEmpty) {
          hasUnrestrictedImage = true;
        } else {
          inferredUsage.addAll(imageUsage);
        }
      }

      images[entry.key as String] = image;
    }
  }

  if ((packUsage == null || packUsage.isEmpty) &&
      !hasUnrestrictedImage &&
      inferredUsage.isNotEmpty) {
    pack['usage'] = [
      if (inferredUsage.contains('emoticon')) 'emoticon',
      if (inferredUsage.contains('sticker')) 'sticker',
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
  return raw
      .whereType<String>()
      .where(_stableImagePackUsages.contains)
      .toSet();
}
