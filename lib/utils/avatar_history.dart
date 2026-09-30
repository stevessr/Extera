import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locally cached list of mxc URIs that were ever used as an avatar (global
/// profile, room icon or per-room member override), newest first. Lets the
/// user re-apply a previous picture without re-uploading it.
abstract final class AvatarHistory {
  static const String _prefKey = 'xyz.extera.avatar_history';
  static const int _maxEntries = 32;

  static List<String> _read(SharedPreferences prefs) =>
      List.of(prefs.getStringList(_prefKey) ?? const <String>[]);

  static bool _isMxcUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'mxc' &&
        uri.hasAuthority &&
        uri.authority.isNotEmpty;
  }

  static Future<void> _write(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, entries.take(_maxEntries).toList());
  }

  /// All known historical avatar mxc URIs, newest first.
  ///
  /// Invalid or duplicated values left by older versions are filtered out so
  /// the picker never tries to render a non-Matrix media URI.
  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    return _read(prefs)
        .where((entry) => _isMxcUri(entry) && seen.add(entry))
        .take(_maxEntries)
        .toList();
  }

  /// Records [mxcUri] at the front of the history, deduplicated.
  static Future<void> record(String mxcUri) async {
    if (!_isMxcUri(mxcUri)) return;
    final prefs = await SharedPreferences.getInstance();
    final entries = _read(prefs)
      ..removeWhere((entry) => entry == mxcUri || !_isMxcUri(entry));
    entries.insert(0, mxcUri);
    await _write(entries);
    Logs().v('AvatarHistory: recorded $mxcUri');
  }

  /// Null-safe convenience for recording avatar values already parsed as URIs.
  static Future<void> recordUri(Uri? mxcUri) async {
    if (mxcUri == null) return;
    await record(mxcUri.toString());
  }
}
