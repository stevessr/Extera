import 'package:matrix/matrix.dart';

/// Resolves the homeserver's account-management URL using stable Matrix OAuth
/// metadata first, while retaining MSC2965 discovery as a compatibility
/// fallback for older deployments.
Future<String?> getAccountManagementUrl(Client client) async {
  try {
    final accountManagementUri =
        (await client.getAuthMetadata()).accountManagementUri;
    if (accountManagementUri != null) return accountManagementUri.toString();
  } catch (error, stackTrace) {
    Logs().d(
      'Stable OAuth account-management metadata is unavailable',
      error,
      stackTrace,
    );
  }

  try {
    return (await client.getWellknown()).additionalProperties
        .tryGetMap<String, Object?>('org.matrix.msc2965.authentication')
        ?.tryGet<String>('account');
  } catch (error, stackTrace) {
    Logs().d(
      'Legacy MSC2965 account-management metadata is unavailable',
      error,
      stackTrace,
    );
    return null;
  }
}
