import 'package:matrix/matrix.dart';

extension ClientProfileExtension on Client {
  /// Fetches the own profile straight from the homeserver, bypassing and
  /// refreshing the SDK's database profile cache (which otherwise serves
  /// entries for up to a day), then announces the update so listeners such
  /// as the drawer pick up the change immediately.
  ///
  /// Call after mutating any own profile field (`setProfileField`,
  /// `setAvatar`, …); the raw API calls never invalidate the cache
  /// themselves, so surfaces reading `fetchOwnProfile` /
  /// `getProfileFromUserId` would keep showing the previous values until a
  /// sync delivers a rewritten member event — or until the cache expires.
  Future<CachedProfileInformation> refreshOwnProfile() async {
    final profile = await getUserProfile(userID!, maxCacheAge: Duration.zero);
    onUserProfileUpdate.add(userID!);
    return profile;
  }
}
