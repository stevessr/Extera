import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/config/animated_emoji_config.dart';

void main() {
  group('animated emoji sprite atlas config', () {
    test('buckets physical sizes for texture sharing', () {
      expect(animatedEmojiAtlasRasterSizeFor(20), 48);
      expect(animatedEmojiAtlasRasterSizeFor(49), 64);
      expect(animatedEmojiAtlasRasterSizeFor(95), 96);
      expect(animatedEmojiAtlasRasterSizeFor(129), 192);
      expect(animatedEmojiAtlasRasterSizeFor(999), 192);
    });

    test('caps sampled animation frame rate and frame count', () {
      expect(
        animatedEmojiAtlasFrameCountFor(const Duration(seconds: 1), 60),
        30,
      );
      expect(
        animatedEmojiAtlasFrameCountFor(const Duration(seconds: 10), 60),
        animatedEmojiAtlasMaxFrames,
      );
      expect(animatedEmojiAtlasFrameCountFor(Duration.zero, 30), 1);
    });
  });
}
