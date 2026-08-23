import 'package:extera_next/utils/matrix_sdk_extensions/synapse_admin_extension.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminUser', () {
    test('parses a full Synapse user object', () {
      final user = AdminUser.fromJson({
        'name': '@alice:example.org',
        'displayname': 'Alice',
        'avatar_url': 'mxc://example.org/abc123',
        'admin': true,
        'deactivated': false,
        'creation_ts': 1000000,
        'last_seen_ts': 2000000,
      });
      expect(user.name, '@alice:example.org');
      expect(user.displayname, 'Alice');
      expect(user.avatarUrl, 'mxc://example.org/abc123');
      expect(user.admin, isTrue);
      expect(user.deactivated, isFalse);
      expect(
        user.creationTs,
        DateTime.fromMillisecondsSinceEpoch(1000000 * 1000),
      );
      expect(
        user.lastSeenTs,
        DateTime.fromMillisecondsSinceEpoch(2000000 * 1000),
      );
    });

    test('defaults flags and tolerates missing optional fields', () {
      final user = AdminUser.fromJson({'name': '@bob:example.org'});
      expect(user.displayname, isNull);
      expect(user.admin, isFalse);
      expect(user.deactivated, isFalse);
      expect(user.creationTs, isNull);
    });

    test('effectiveName prefers non-empty displayname', () {
      expect(
        AdminUser.fromJson({
          'name': '@a:x.org',
          'displayname': 'Shown',
        }).effectiveName,
        'Shown',
      );
      expect(
        AdminUser.fromJson({
          'name': '@a:x.org',
          'displayname': '',
        }).effectiveName,
        '@a:x.org',
      );
    });

    test('toJson roundtrip keeps editable fields', () {
      final user = AdminUser(
        name: '@carol:example.org',
        displayname: 'Carol',
        avatarUrl: 'mxc://example.org/img',
        admin: true,
        deactivated: true,
        creationTs: DateTime.now(),
      );
      final json = user.toJson();
      expect(json['name'], '@carol:example.org');
      expect(json['admin'], isTrue);
      expect(json['deactivated'], isTrue);
      // Non-editable fields must not be sent back to the server.
      expect(json.containsKey('creation_ts'), isFalse);
      expect(AdminUser.fromJson(json).effectiveName, 'Carol');
    });
  });

  group('AdminRoomSummary', () {
    test('displayName falls back alias then room id', () {
      expect(
        AdminRoomSummary.fromJson({
          'room_id': '!r:x.org',
          'name': 'Named',
          'canonical_alias': '#alias:x.org',
          'joined_members': 3,
        }).displayName,
        'Named',
      );
      expect(
        AdminRoomSummary.fromJson({
          'room_id': '!r:x.org',
          'canonical_alias': '#alias:x.org',
        }).displayName,
        '#alias:x.org',
      );
      expect(
        AdminRoomSummary.fromJson({'room_id': '!r:x.org'}).displayName,
        '!r:x.org',
      );
    });

    test('encryption presence marks room encrypted', () {
      expect(
        AdminRoomSummary.fromJson({
          'room_id': '!r:x.org',
          'encryption': 'm.megolm.v1.v1',
        }).encrypted,
        isTrue,
      );
      expect(
        AdminRoomSummary.fromJson({'room_id': '!r:x.org'}).encrypted,
        isFalse,
      );
    });

    test('non-int member counts degrade to zero', () {
      expect(
        AdminRoomSummary.fromJson({
          'room_id': '!r:x.org',
          'joined_members': 'many',
        }).joinedMembers,
        0,
      );
    });
  });

  group('AdminUsersPage / AdminRoomsPage', () {
    test('expose cursors only when present', () {
      const page = AdminUsersPage(users: [], nextToken: 50);
      expect(page.nextToken, 50);
      const last = AdminUsersPage(users: []);
      expect(last.nextToken, isNull);
      const rooms = AdminRoomsPage(rooms: [], total: 12, nextBatch: 25);
      expect(rooms.total, 12);
      expect(rooms.nextBatch, 25);
    });
  });
}
