/// Performance safeguards for animated emoji rendering.
///
/// Keep this separate from user-facing settings: this is an application-level
/// safety limit intended to prevent a single message from instantiating too
/// many animation players at once.
const int maxAnimatedEmojiPerMessage = 10;
