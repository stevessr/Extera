import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:extera_next/utils/matrix_sdk_extensions/msc2666_extension.dart';

void main() {
  group('supportsStableMutualRooms', () {
    test('recognizes Matrix v1.19 and newer', () {
      expect(
        supportsStableMutualRooms(
          matrix.GetVersionsResponse(versions: ['v1.19']),
        ),
        isTrue,
      );
      expect(
        supportsStableMutualRooms(
          matrix.GetVersionsResponse(versions: ['v1.20']),
        ),
        isTrue,
      );
    });

    test('does not treat older Matrix versions as stable', () {
      expect(
        supportsStableMutualRooms(
          matrix.GetVersionsResponse(versions: ['r0.6.1', 'v1.18']),
        ),
        isFalse,
      );
    });

    test('keeps the transitional stable feature flag compatible', () {
      expect(
        supportsStableMutualRooms(
          matrix.GetVersionsResponse(
            versions: ['v1.18'],
            unstableFeatures: {
              'uk.half-shot.msc2666.query_mutual_rooms.stable': true,
            },
          ),
        ),
        isTrue,
      );
    });
  });
}
