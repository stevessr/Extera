import 'package:matrix/matrix.dart';

extension CryptoBackupExtension on Client {
  /// Checks the two cross-signing secrets without using the SDK's combined
  /// async check. Keeping the awaited checks separate avoids a dart2wasm
  /// completion with `null` when a cache entry is missing.
  Future<bool> hasCachedCrossSigningKeys() async {
    await accountDataLoading;

    final encryption = this.encryption;
    if (encryption == null || !encryption.crossSigning.enabled) {
      return false;
    }

    final selfSigningKey = await encryption.ssss.getCached(
      EventTypes.CrossSigningSelfSigning,
    );
    if (selfSigningKey == null) return false;

    final userSigningKey = await encryption.ssss.getCached(
      EventTypes.CrossSigningUserSigning,
    );
    return userSigningKey != null;
  }
}
