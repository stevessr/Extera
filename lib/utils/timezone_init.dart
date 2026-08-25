import 'timezone_initializer.dart' as impl;

bool _initialized = false;

/// Parses the timezone database on first use instead of at app startup:
/// the only consumers are the settings timezone picker and the profile
/// timezone clock, both low-frequency pages. Idempotent.
void ensureTimeZonesInitialized() {
  if (_initialized) return;
  _initialized = true;
  impl.initializeTimeZones();
}
