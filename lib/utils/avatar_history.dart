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

  static Future<void> _write(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, entries.take(_maxEntries).toList());
  }

  /// All known historical avatar mxc URIs, newest first.
  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).where((e) => Uri.tryParse(e) != null).toList();
  }

  /// Records [mxcUri] at the front of the history, deduplicated.
  static Future<void> record(String mxcUri) async {
    if (mxcUri.isEmpty || Uri.tryParse(mxcUri)?.scheme != 'mxc') return;
    final prefs = await SharedPreferences.getInstance();
    final entries = _read(prefs)..remove(mxcUri);
    entries.insert(0, mxcUri);
    await _write(entries);
    Logs().v('AvatarHistory: recorded $mxcUri');
  }
}
