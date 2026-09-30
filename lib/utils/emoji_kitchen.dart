import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime Emoji Kitchen compatibility data.
///
/// Google exposes the generated artwork through gstatic, but does not expose a
/// stable public API for discovering supported pairs. The compressed
/// compatibility table is maintained by MattFor/emoji-mixer (MIT) from Emoji
/// Kitchen metadata. Keeping it remote avoids adding the much larger full
/// metadata set to Extera's app bundle.
class EmojiKitchenDataSource {
  EmojiKitchenDataSource._();

  static final EmojiKitchenDataSource instance = EmojiKitchenDataSource._();

  static const compatibilityUri =
      'https://raw.githubusercontent.com/MattFor/emoji-mixer/master/compatibility.json';
  static const _cacheKey = 'emoji_kitchen_compatibility_v1';
  static const _cacheTimeKey = 'emoji_kitchen_compatibility_v1_saved_at';
  static const _cacheMaxAge = Duration(days: 30);

  Map<String, dynamic>? _data;
  Future<void>? _loading;
  final Map<String, List<EmojiKitchenCombination>> _combinationCache = {};

  bool get isLoaded => _data != null;

  Future<void> ensureLoaded({bool forceRefresh = false}) {
    if (!forceRefresh && _data != null) {
      return SynchronousFuture<void>(null);
    }
    if (!forceRefresh && _loading != null) return _loading!;

    final loading = _load(forceRefresh: forceRefresh);
    _loading = loading;
    return loading.whenComplete(() {
      if (identical(_loading, loading)) _loading = null;
    });
  }

  Future<void> _load({required bool forceRefresh}) async {
    final preferences = await SharedPreferences.getInstance();
    final cached = preferences.getString(_cacheKey);
    final savedAt = preferences.getInt(_cacheTimeKey);
    final now = DateTime.now();
    final cacheIsFresh =
        !forceRefresh &&
        cached != null &&
        savedAt != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(savedAt)) <
            _cacheMaxAge;

    if (cacheIsFresh) {
      try {
        _installData(await compute(_decodeCompatibilityData, cached));
        return;
      } catch (error) {
        debugPrint('Ignoring invalid Emoji Kitchen cache: $error');
      }
    }

    try {
      final response = await http
          .get(Uri.parse(compatibilityUri))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw EmojiKitchenException(
          'Compatibility metadata returned HTTP ${response.statusCode}.',
        );
      }

      final body = response.body;
      _installData(await compute(_decodeCompatibilityData, body));

      // SharedPreferences is a best-effort cross-platform persistent cache.
      // Some web environments can have a very small storage quota, so a cache
      // write failure must never make Emoji Kitchen unusable.
      try {
        await preferences.setString(_cacheKey, body);
        await preferences.setInt(_cacheTimeKey, now.millisecondsSinceEpoch);
      } catch (error) {
        debugPrint('Could not persist Emoji Kitchen metadata cache: $error');
      }
      return;
    } catch (error) {
      // A stale cache is much better than making the feature unavailable while
      // offline or when GitHub's raw CDN is temporarily unreachable.
      if (cached != null) {
        try {
          _installData(await compute(_decodeCompatibilityData, cached));
          return;
        } catch (cacheError) {
          debugPrint('Stale Emoji Kitchen cache is invalid: $cacheError');
        }
      }
      if (error is EmojiKitchenException) rethrow;
      throw EmojiKitchenException(
        'Unable to load Emoji Kitchen metadata.',
        error,
      );
    }
  }

  void _installData(Map<String, dynamic> data) {
    if (data[r'$e'] is! List || data[r'$d'] is! List) {
      throw const EmojiKitchenException('Invalid Emoji Kitchen metadata.');
    }
    _data = data;
    _combinationCache.clear();
  }

  /// Finds the database key corresponding to [emoji]. Emoji presentation
  /// selectors differ between platforms, so exact matching is attempted first
  /// and then falls back to the same leading-codepoint matching used by the
  /// reference emoji-mixer implementation.
  String? supportedCodepointFor(String emoji) {
    final data = _data;
    if (data == null || emoji.isEmpty) return null;

    final full = emoji.runes
        .map((rune) => rune.toRadixString(16).toLowerCase())
        .join('-');
    if (data.containsKey(full)) return full;

    final withoutPresentation = full
        .split('-')
        .where((part) => part != 'fe0f')
        .join('-');
    if (data.containsKey(withoutPresentation)) return withoutPresentation;

    final first = emoji.runes.first.toRadixString(16).toLowerCase();
    String? fallback;
    for (final key in data.keys) {
      if (key.startsWith(r'$')) continue;
      if (key == first) return key;
      if (fallback == null && key.startsWith('$first-')) fallback = key;
    }
    return fallback;
  }

  List<EmojiKitchenCombination> combinationsFor(String selectedCodepoint) {
    final cached = _combinationCache[selectedCodepoint];
    if (cached != null) return cached;

    final data = _data;
    if (data == null) {
      throw const EmojiKitchenException(
        'Emoji Kitchen metadata is not loaded.',
      );
    }

    final emojiTable = data[r'$e'];
    final dateTable = data[r'$d'];
    if (emojiTable is! List || dateTable is! List) {
      throw const EmojiKitchenException('Invalid Emoji Kitchen metadata.');
    }

    final selectedStored = _storedEmojiValue(selectedCodepoint);
    final newestByPartner = <String, EmojiKitchenCombination>{};

    void inspect(String anchor, dynamic rawEntry) {
      if (rawEntry is! List || rawEntry.length < 2) return;
      final emojiIndex = rawEntry[0];
      final dateIndex = rawEntry[1];
      if (emojiIndex is! num || dateIndex is! num) return;
      if (emojiIndex < 0 || emojiIndex >= emojiTable.length) return;
      if (dateIndex < 0 || dateIndex >= dateTable.length) return;

      final rawOther = emojiTable[emojiIndex.toInt()];
      final otherCodepoint = _expandedEmojiValue(rawOther);
      if (otherCodepoint == null) return;

      late final String partner;
      if (anchor == selectedCodepoint) {
        partner = otherCodepoint;
      } else if (_storedEmojiValue(otherCodepoint) == selectedStored) {
        partner = anchor;
      } else {
        return;
      }

      final combination = EmojiKitchenCombination(
        leftCodepoint: anchor,
        rightCodepoint: otherCodepoint,
        partnerCodepoint: partner,
        date: dateTable[dateIndex.toInt()].toString(),
      );
      final current = newestByPartner[partner];
      if (current == null || combination.date.compareTo(current.date) > 0) {
        newestByPartner[partner] = combination;
      }
    }

    // Direct entries first so the result order remains close to Gboard's
    // source metadata. Then include reverse-only pairs; Google URLs are not
    // guaranteed to be symmetric, so their stored orientation is preserved.
    final direct = data[selectedCodepoint];
    if (direct is List) {
      for (final entry in direct) {
        inspect(selectedCodepoint, entry);
      }
    }

    for (final entry in data.entries) {
      final anchor = entry.key;
      if (anchor.startsWith(r'$') || anchor == selectedCodepoint) continue;
      final combinations = entry.value;
      if (combinations is! List) continue;
      for (final combination in combinations) {
        inspect(anchor, combination);
      }
    }

    final result = List<EmojiKitchenCombination>.unmodifiable(
      newestByPartner.values,
    );
    _combinationCache[selectedCodepoint] = result;
    return result;
  }

  static Object _storedEmojiValue(String value) {
    if (value.contains('-')) return value;
    return int.tryParse(value, radix: 16) ?? value;
  }

  static String? _expandedEmojiValue(dynamic value) {
    if (value is num) return value.toInt().toRadixString(16);
    if (value is String && value.isNotEmpty) return value.toLowerCase();
    return null;
  }
}

class EmojiKitchenCombination {
  final String leftCodepoint;
  final String rightCodepoint;
  final String partnerCodepoint;
  final String date;

  const EmojiKitchenCombination({
    required this.leftCodepoint,
    required this.rightCodepoint,
    required this.partnerCodepoint,
    required this.date,
  });

  String get partnerEmoji => codepointToEmoji(partnerCodepoint);

  Uri get imageUri {
    final left = _gstaticPart(leftCodepoint);
    final right = _gstaticPart(rightCodepoint);
    return Uri.parse(
      'https://www.gstatic.com/android/keyboard/emojikitchen/'
      '$date/$left/${left}_$right.png',
    );
  }

  String get fileName =>
      'emoji-kitchen-${leftCodepoint}_$rightCodepoint-$date.png';

  static String codepointToEmoji(String codepoint) {
    try {
      return String.fromCharCodes(
        codepoint.split('-').map((part) => int.parse(part, radix: 16)),
      );
    } catch (_) {
      return '🙂';
    }
  }

  static String _gstaticPart(String codepoint) =>
      codepoint.toLowerCase().split('-').map((part) => 'u$part').join('-');
}

class EmojiKitchenException implements Exception {
  final String message;
  final Object? cause;

  const EmojiKitchenException(this.message, [this.cause]);

  @override
  String toString() => message;
}

Map<String, dynamic> _decodeCompatibilityData(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const EmojiKitchenException('Invalid Emoji Kitchen metadata.');
  }
  return decoded;
}
