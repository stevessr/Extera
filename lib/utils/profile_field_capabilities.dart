import 'package:matrix/matrix.dart';

/// Evaluates the stable `m.profile_fields` capability for one profile field.
///
/// A missing capability is treated as unrestricted for compatibility, as the
/// Matrix specification requires for servers which otherwise advertise the
/// stable custom-profile-fields API.
bool profileFieldCanBeModified(
  ProfileFieldsCapability? capability,
  String field,
) {
  if (capability == null) return true;
  if (!capability.enabled) return false;

  final allowed = capability.allowed;
  if (allowed != null) return allowed.contains(field);

  final disallowed = capability.disallowed;
  return disallowed == null || !disallowed.contains(field);
}

extension ProfileFieldCapabilitiesExtension on Client {
  /// Checks whether the current user may modify [field].
  ///
  /// Stable `m.profile_fields` is authoritative. When it is absent, retain the
  /// deprecated display-name/avatar capabilities as an old-server fallback;
  /// all other fields keep the historical permissive behaviour.
  Future<bool> canModifyOwnProfileField(String field) async {
    try {
      final capabilities = await getCapabilities();
      final profileFields = capabilities.mProfileFields;
      if (profileFields != null) {
        return profileFieldCanBeModified(profileFields, field);
      }

      if (field == 'displayname' && capabilities.mSetDisplayname != null) {
        return capabilities.mSetDisplayname!.enabled;
      }
      if (field == 'avatar_url' && capabilities.mSetAvatarUrl != null) {
        return capabilities.mSetAvatarUrl!.enabled;
      }
      return true;
    } catch (error, stackTrace) {
      // `/capabilities` is rate-limited and some older homeservers do not
      // implement it correctly. Preserve Extera's previous behaviour rather
      // than making profile editing unusable when capability discovery fails.
      Logs().d(
        'Unable to resolve m.profile_fields capability',
        error,
        stackTrace,
      );
      return true;
    }
  }
}
