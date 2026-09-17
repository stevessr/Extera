/// Performance safeguards for animated emoji rendering.
///
/// Keep these separate from user-facing settings: they are application-level
/// limits intended to keep animation-heavy messages from degrading scrolling
/// and battery life.
const int maxAnimatedEmojiPerMessage = 10;

/// Maximum refresh rate of the single shared animated-emoji clock.
const int animatedEmojiAtlasMaxFps = 30;

/// Upper bound on the number of frames rasterized into one sprite atlas.
const int animatedEmojiAtlasMaxFrames = 90;

/// Approximate GPU-memory budget for cached sprite atlases.
const int animatedEmojiAtlasCacheBytes = 32 * 1024 * 1024;

/// Physical-pixel tile sizes used for atlases. Keeping a few buckets makes
/// identical emoji at normal chat sizes share the same texture.
const List<int> animatedEmojiAtlasRasterBuckets = [48, 64, 96, 128, 192];

int animatedEmojiAtlasRasterSizeFor(double physicalPixels) {
  if (!physicalPixels.isFinite || physicalPixels <= 0) {
    return animatedEmojiAtlasRasterBuckets.first;
  }
  for (final bucket in animatedEmojiAtlasRasterBuckets) {
    if (physicalPixels <= bucket) return bucket;
  }
  return animatedEmojiAtlasRasterBuckets.last;
}

int animatedEmojiAtlasFrameCountFor(
  Duration duration,
  double compositionFps,
) {
  if (duration <= Duration.zero) return 1;
  final safeFps = compositionFps.isFinite && compositionFps > 0
      ? compositionFps
      : 1.0;
  final targetFps = safeFps > animatedEmojiAtlasMaxFps
      ? animatedEmojiAtlasMaxFps.toDouble()
      : safeFps;
  final seconds =
      duration.inMicroseconds / Duration.microsecondsPerSecond.toDouble();
  final frames = (seconds * targetFps).ceil();
  if (frames < 1) return 1;
  if (frames > animatedEmojiAtlasMaxFrames) {
    return animatedEmojiAtlasMaxFrames;
  }
  return frames;
}
