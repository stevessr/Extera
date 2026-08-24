import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/memoized_tile_cache.dart';

void main() {
  test('reuses the same instance while deps compare equal', () {
    final cache = MemoizedTileCache<({int a, String b}), Object>();
    var builds = 0;
    final tile = Object();

    final first = cache.get('\$a', (a: 1, b: 'x'), () {
      builds++;
      return tile;
    });
    final second = cache.get('\$a', (a: 1, b: 'x'), () {
      builds++;
      return Object();
    });

    expect(identical(first, second), isTrue);
    expect(builds, 1);
  });

  test('rebuilds when any dep changes', () {
    final cache = MemoizedTileCache<int, Object>();

    final first = cache.get('\$a', 1, () => Object());
    final changed = cache.get('\$a', 2, () => Object());

    expect(identical(first, changed), isFalse);
    expect(cache.buildCount, 2);
    // The new deps stick around for subsequent lookups.
    final stable = cache.get('\$a', 2, () => Object());
    expect(identical(changed, stable), isTrue);
  });

  test('markDirty forces exactly one rebuild per lookup', () {
    final cache = MemoizedTileCache<int, Object>();
    final initial = cache.get('\$a', 1, () => Object());

    cache.markDirty(const {'\$a'});
    final rebuilt = cache.get('\$a', 1, () => Object());
    expect(identical(initial, rebuilt), isFalse);

    // Dirty flag was consumed; the next lookup hits again.
    final again = cache.get('\$a', 1, () => Object());
    expect(identical(rebuilt, again), isTrue);
    expect(cache.buildCount, 2);
  });

  test('dirty IDs without entries are harmless and bounded', () {
    final cache = MemoizedTileCache<int, int>(dirtyCapacity: 4);
    cache.markDirty(const ['\$1', '\$2', '\$3', '\$4']);
    // Over capacity: dirty set clears, entry still absent -> build happens.
    expect(cache.get('\$1', 0, () => 42), 42);
    expect(cache.get('\$1', 0, () => 99), 42);
  });

  test('evicts least recently used beyond maxEntries', () {
    final cache = MemoizedTileCache<int, Object>(maxEntries: 2);
    final a = cache.get('\$a', 1, () => Object());
    final b = cache.get('\$b', 1, () => Object());
    // Touch \$a so it becomes most-recently-used.
    expect(identical(cache.get('\$a', 1, () => Object()), a), isTrue);

    cache.get('\$c', 1, () => Object()); // evicts \$b

    final aAgain = cache.get('\$a', 1, () => Object());
    expect(identical(aAgain, a), isTrue); // survived
    expect(
      identical(cache.get('\$b', 1, () => Object()), b),
      isFalse,
    ); // was evicted
  });

  test('clear drops every entry and pending dirtiness', () {
    final cache = MemoizedTileCache<int, Object>();
    final initial = cache.get('\$a', 1, () => Object());
    var seen = 0;
    cache.forEach((id, deps, _) => seen++);
    expect(seen, 1);

    cache.clear();
    expect(seen, 1); // forEach snapshot unchanged
    final rebuilt = cache.get('\$a', 1, () => Object());
    expect(identical(rebuilt, initial), isFalse);
  });
}
