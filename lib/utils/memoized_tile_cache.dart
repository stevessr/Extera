/// Bounded memoization of expensive-to-build tiles keyed by string ID.
///
/// Callers compare an immutable snapshot of every input that influences the
/// rendered output (a Dart record works well: records compare
/// structurally). When the snapshot equals the one a tile was built with,
/// the previously built instance is returned so Flutter's element tree can
/// skip rebuilding that subtree entirely.
///
/// Entries are invalidated two ways:
/// - [markDirty] drops knowledge for specific IDs (e.g. when an aggregation
///   target received a reaction/edit whose change is invisible in the deps).
/// - The least-recently-used entry is evicted once [maxEntries] is exceeded.
class MemoizedTileCache<D, T> {
  MemoizedTileCache({this.maxEntries = 128, this.dirtyCapacity = 1024});

  final int maxEntries;

  /// Upper bound for pending dirty IDs that never got looked up (e.g.
  /// updates for events outside the viewport); prevents unbounded growth.
  final int dirtyCapacity;

  final Map<String, ({D deps, T tile})> _entries = {};
  final Set<String> _dirty = {};
  int _buildCount = 0;

  /// Number of times [get] had to invoke [build] (exposed for tests).
  int get buildCount => _buildCount;

  /// Returns the cached tile for [id] when [deps] are unchanged; otherwise
  /// builds via [build] and caches the result.
  T get(String id, D deps, T Function() build) {
    if (_dirty.length >= dirtyCapacity) _dirty.clear();
    if (!_dirty.contains(id)) {
      final cached = _entries[id];
      if (cached != null && cached.deps == deps) {
        // Re-insert so the entry becomes most-recently-used.
        _entries.remove(id);
        _entries[id] = cached;
        return cached.tile;
      }
    }
    _dirty.remove(id);
    final tile = build();
    _buildCount++;
    _entries[id] = (deps: deps, tile: tile);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return tile;
  }

  /// Flags IDs whose rendered output may have changed even though their
  /// inputs snapshot would still compare equal; their next lookup rebuilds.
  void markDirty(Iterable<String> ids) => _dirty.addAll(ids);

  /// Iterates every cached entry (most-recent insertion order last).
  void forEach(void Function(String id, D deps, T tile) action) =>
      _entries.forEach((id, entry) => action(id, entry.deps, entry.tile));

  void clear() {
    _entries.clear();
    _dirty.clear();
  }
}
