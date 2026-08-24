import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/stream_extension.dart';

void main() {
  group('StreamExtension.rateLimit', () {
    test('supports multiple simultaneous listeners', () async {
      final source = StreamController<void>.broadcast();
      final limited = source.stream.rateLimit(const Duration(seconds: 1));

      final first = <bool>[];
      final second = <bool>[];
      // A single-subscription controller would throw
      // "Bad state: Stream has already been listened to" here.
      final sub1 = limited.listen(first.add);
      final sub2 = limited.listen(second.add);

      source.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(first, [true]);
      expect(second, [true]);

      await sub1.cancel();
      await sub2.cancel();
      unawaited(source.close());
    });

    test('emits only one event per rate-limit window', () async {
      final source = StreamController<void>.broadcast();
      final limited = source.stream.rateLimit(const Duration(milliseconds: 50));
      final events = <bool>[];
      final sub = limited.listen(events.add);

      for (var i = 0; i < 10; i++) {
        source.add(null);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, [true]);

      // After the window the trailing burst replays at most once.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events, [true, true]);

      unawaited(sub.cancel());
      unawaited(source.close());
    });

    test(
      'releases the source subscription when all listeners cancel',
      () async {
        final source = StreamController<int>.broadcast();
        var received = 0;
        final sub = source.stream
            .rateLimit(const Duration(seconds: 1))
            .listen((_) => received++);

        source.add(1);
        await Future<void>.delayed(Duration.zero);
        expect(received, 1);

        await sub.cancel();

        source.add(2);
        await Future<void>.delayed(Duration.zero);
        expect(received, 1);
        unawaited(source.close());
      },
    );
  });
}
