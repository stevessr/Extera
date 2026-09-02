import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/profile_field_capabilities.dart';

void main() {
  group('profileFieldCanBeModified', () {
    test('allows fields when the capability is absent', () {
      expect(profileFieldCanBeModified(null, 'xyz.extera.about'), isTrue);
    });

    test('denies every field when profile modification is disabled', () {
      final capability = ProfileFieldsCapability(enabled: false);

      expect(profileFieldCanBeModified(capability, 'displayname'), isFalse);
      expect(profileFieldCanBeModified(capability, 'm.tz'), isFalse);
    });

    test('allowed is an allow-list and takes precedence over disallowed', () {
      final capability = ProfileFieldsCapability(
        enabled: true,
        allowed: ['displayname', 'm.tz'],
        disallowed: ['displayname'],
      );

      expect(profileFieldCanBeModified(capability, 'displayname'), isTrue);
      expect(profileFieldCanBeModified(capability, 'm.tz'), isTrue);
      expect(profileFieldCanBeModified(capability, 'avatar_url'), isFalse);
    });

    test('disallowed blocks only the listed fields', () {
      final capability = ProfileFieldsCapability(
        enabled: true,
        disallowed: ['avatar_url', 'xyz.extera.about'],
      );

      expect(profileFieldCanBeModified(capability, 'avatar_url'), isFalse);
      expect(
        profileFieldCanBeModified(capability, 'xyz.extera.about'),
        isFalse,
      );
      expect(profileFieldCanBeModified(capability, 'displayname'), isTrue);
    });

    test('allows all fields when no lists restrict an enabled capability', () {
      final capability = ProfileFieldsCapability(enabled: true);

      expect(profileFieldCanBeModified(capability, 'displayname'), isTrue);
      expect(
        profileFieldCanBeModified(capability, 'custom.example.field'),
        isTrue,
      );
    });
  });
}
