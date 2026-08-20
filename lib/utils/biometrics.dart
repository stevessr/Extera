import 'package:local_auth/local_auth.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/platform_infos.dart';

/// Thin wrapper around [LocalAuthentication] that never throws.
///
/// Biometrics are an alternative way to get past the app lock, so every
/// failure has to degrade into "use the passcode" rather than into an error.
abstract class Biometrics {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this device can authenticate the user biometrically right now.
  ///
  /// Requires hardware support *and* an enrolled fingerprint or face.
  static Future<bool> get isAvailable async {
    if (!PlatformInfos.isMobile) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (e, s) {
      Logs().w('Unable to query the available biometrics', e, s);
      return false;
    }
  }

  /// Prompts for a fingerprint or face scan.
  ///
  /// Returns whether the user was authenticated. Device credentials are
  /// deliberately not offered as a fallback: the app has its own passcode for
  /// that, and unlocking with the device PIN would weaken the app lock.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e, s) {
      Logs().w('Biometric authentication failed', e, s);
      return false;
    }
  }
}
