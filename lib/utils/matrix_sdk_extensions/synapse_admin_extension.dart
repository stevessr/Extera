import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix.dart' as matrix;

extension SynapseAdmin on matrix.Client {
  Future<List<dynamic>> getEventReports({int from = 0, int limit = 10}) async {
    final requestUri = Uri(
      path: '/_synapse/admin/v1/event_reports',
      query: 'from=$from&limit=$limit&order_by=received_ts&dir=b',
    );

    if (baseUri == null) return [];

    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer $accessToken';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);
    final responseString = utf8.decode(responseBody);
    final json = jsonDecode(responseString);
    return json['event_reports'];
  }

  Future<matrix.Event?> getReportedEvent(int id) async {
    final requestUri = Uri(path: '/_synapse/admin/v1/event_reports/$id');

    if (baseUri == null) return null;
    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer $accessToken';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);
    final responseString = utf8.decode(responseBody);
    final json = jsonDecode(responseString);

    final room = getRoomById(json['room_id']);

    if (room == null) return null;

    return matrix.Event(
      content: json['event_json']['content'],
      type: json['event_json']['type'],
      eventId: json['event_id'],
      senderId: json['sender'],
      originServerTs: DateTime.fromMillisecondsSinceEpoch(
        json['event_json']['origin_server_ts'],
      ),
      room: room,
    );
  }

  Future<bool> isSynapseAdministrator() async {
    print('Checking if I am admin...');
    print('User ID: $userID');
    if (userID == null) return false;
    final requestUri = Uri(path: '/_synapse/admin/v1/users/$userID/admin');

    print('Base URL: ${baseUri.toString()}');
    if (baseUri == null) return false;
    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer $accessToken';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);
    final responseString = utf8.decode(responseBody);
    final json = jsonDecode(responseString);
    print('Response from endpoint: $responseString');
    return json['admin'];
  }
}

/// Sends an authenticated Synapse Admin API request and returns the decoded
/// JSON body. Non-2xx responses raise through
/// [matrix.Client.unexpectedResponse].
Future<Object?> _adminSend(
  matrix.Client client,
  String method,
  String path, {
  Object? body,
}) async {
  if (client.baseUri == null) {
    throw Exception('No homeserver base URL');
  }
  final request = Request(method, client.baseUri!.resolveUri(Uri(path: path)));
  request.headers['authorization'] = 'Bearer ${client.accessToken}';
  if (body != null) {
    request.headers['content-type'] = 'application/json';
    request.body = jsonEncode(body);
  }
  final response = await client.httpClient.send(request);
  final responseBody = await response.stream.toBytes();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    client.unexpectedResponse(response, responseBody);
  }
  return jsonDecode(utf8.decode(responseBody));
}

/// Result cache for [SynapseAdminManagement.isSynapseAdministratorCached],
/// keyed by user ID so the probe runs at most once per account per app run.
final Map<String, bool> _synapseAdminCache = <String, bool>{};

class AdminUser {
  AdminUser({
    required this.name,
    this.displayname,
    this.avatarUrl,
    this.admin = false,
    this.deactivated = false,
    this.creationTs,
    this.lastSeenTs,
  });

  factory AdminUser.fromJson(Map<String, Object?> json) => AdminUser(
    name: json['name'] as String,
    displayname: json['displayname'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    admin: json['admin'] == true,
    deactivated: json['deactivated'] == true,
    creationTs: json['creation_ts'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['creation_ts'] as int) * 1000,
          )
        : null,
    lastSeenTs: json['last_seen_ts'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['last_seen_ts'] as int) * 1000,
          )
        : null,
  );

  final String name;
  final String? displayname;
  final String? avatarUrl;
  bool admin;
  bool deactivated;
  final DateTime? creationTs;
  final DateTime? lastSeenTs;

  Map<String, Object?> toJson() => {
    'name': name,
    if (displayname != null) 'displayname': displayname,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    'admin': admin,
    'deactivated': deactivated,
  };

  String get effectiveName {
    final displayname = this.displayname;
    return (displayname != null && displayname.isNotEmpty) ? displayname : name;
  }
}

class AdminUsersPage {
  const AdminUsersPage({required this.users, this.nextToken});

  final List<AdminUser> users;

  /// Opaque cursor for the next page, null when this is the last page.
  final int? nextToken;
}

class AdminRoomSummary {
  const AdminRoomSummary({
    required this.roomId,
    this.name,
    this.canonicalAlias,
    this.topic,
    this.joinedMembers = 0,
    this.encrypted = false,
  });

  factory AdminRoomSummary.fromJson(Map<String, Object?> json) =>
      AdminRoomSummary(
        roomId: json['room_id'] as String,
        name: json['name'] as String?,
        canonicalAlias: json['canonical_alias'] as String?,
        topic: json['topic'] as String?,
        joinedMembers: json['joined_members'] is int
            ? json['joined_members'] as int
            : 0,
        encrypted: json['encryption'] != null,
      );

  final String roomId;
  final String? name;
  final String? canonicalAlias;
  final String? topic;
  final int joinedMembers;
  final bool encrypted;

  String get displayName => switch ((
    name?.isNotEmpty ?? false,
    canonicalAlias?.isNotEmpty ?? false,
  )) {
    (true, _) => name!,
    (_, true) => canonicalAlias!,
    _ => roomId,
  };
}

class AdminRoomsPage {
  const AdminRoomsPage({
    required this.rooms,
    required this.total,
    this.nextBatch,
  });

  final List<AdminRoomSummary> rooms;
  final int total;

  /// Offset to pass as `from` for the next page, null when exhausted.
  final int? nextBatch;
}

extension SynapseAdminManagement on matrix.Client {
  /// Cached admin probe: true only when the server answered that this user is
  /// a server admin. Network or authorization errors count as "not admin" so
  /// non-Synapse servers never surface the section.
  Future<bool> isSynapseAdministratorCached() async {
    final userId = userID;
    if (userId == null) return false;
    final cached = _synapseAdminCache[userId];
    if (cached != null) return cached;
    try {
      final isAdmin = await isSynapseAdministrator();
      _synapseAdminCache[userId] = isAdmin;
      return isAdmin;
    } catch (_) {
      _synapseAdminCache[userId] = false;
      return false;
    }
  }

  /// Server name and version from `/_synapse/admin/v1/server_version`.
  Future<Map<String, Object?>> adminServerVersion() async {
    final json = await _adminSend(
      this,
      'GET',
      '/_synapse/admin/v1/server_version',
    );
    return Map<String, Object?>.from(json! as Map);
  }

  Future<AdminUsersPage> adminListUsers({
    String? searchTerm,
    int from = 0,
    int limit = 50,
  }) async {
    final queryParameters = <String, String>{
      'from': '$from',
      'limit': '$limit',
      'order_by': 'name',
      'dir': 'f',
      if (searchTerm != null && searchTerm.isNotEmpty)
        'search_term': searchTerm,
    };
    final requestUri = Uri(
      path: '/_synapse/admin/v1/users',
      queryParameters: queryParameters,
    );
    final json = await _adminSend(this, 'GET', requestUri.toString());
    return _parseUsersPage(json);
  }

  Future<AdminUser> adminGetUser(String userId) async {
    final json = await _adminSend(
      this,
      'GET',
      '/_synapse/admin/v1/users/$userId',
    );
    return AdminUser.fromJson(Map<String, Object?>.from(json! as Map));
  }

  /// PUTs profile fields such as `displayname`, `avatar_url`, `admin` or
  /// `deactivated`, matching the Synapse Admin API.
  Future<void> adminEditUser(String userId, Map<String, Object?> fields) =>
      _adminSend(this, 'PUT', '/_synapse/admin/v1/users/$userId', body: fields);

  Future<void> adminResetPassword(
    String userId,
    String newPassword, {
    bool logoutDevices = true,
  }) => _adminSend(
    this,
    'POST',
    '/_synapse/admin/v1/reset_password/$userId',
    body: {'new_password': newPassword, 'logout_devices': logoutDevices},
  );

  Future<void> adminDeactivateUser(String userId, {bool erase = false}) =>
      _adminSend(
        this,
        'POST',
        '/_synapse/admin/v1/deactivate/$userId',
        body: {'erase': erase},
      );

  Future<AdminRoomsPage> adminListRooms({
    String? searchTerm,
    int from = 0,
    int limit = 50,
  }) async {
    final queryParameters = <String, String>{
      'from': '$from',
      'limit': '$limit',
      'order_by': 'name',
      'dir': 'f',
      if (searchTerm != null && searchTerm.isNotEmpty)
        'search_term': searchTerm,
    };
    final requestUri = Uri(
      path: '/_synapse/admin/v1/rooms',
      queryParameters: queryParameters,
    );
    final json = await _adminSend(this, 'GET', requestUri.toString());
    return _parseRoomsPage(json);
  }

  /// Deletes (shuts down) a room, optionally purging history and blocking
  /// recreation. Returns the number of locally kicked members on success.
  Future<int> adminDeleteRoom(
    String roomId, {
    bool purge = true,
    bool block = false,
  }) async {
    final json = await _adminSend(
      this,
      'DELETE',
      '/_synapse/admin/v1/rooms/$roomId',
      body: {'block': block, 'purge': purge},
    );
    final kicked = (json! as Map)['kicked_users'];
    return kicked is int ? kicked : 0;
  }
}

AdminUsersPage _parseUsersPage(Object? json) {
  final map = json! as Map;
  final rawUsers = map['users'] as List<dynamic>? ?? const [];
  return AdminUsersPage(
    users: rawUsers
        .map((u) => AdminUser.fromJson(Map<String, Object?>.from(u as Map)))
        .toList(),
    nextToken: map['next_token'] is int ? map['next_token'] as int : null,
  );
}

AdminRoomsPage _parseRoomsPage(Object? json) {
  final map = json! as Map;
  final rawRooms = map['rooms'] as List<dynamic>? ?? const [];
  return AdminRoomsPage(
    rooms: rawRooms
        .map(
          (r) => AdminRoomSummary.fromJson(Map<String, Object?>.from(r as Map)),
        )
        .toList(),
    total: map['total_rooms'] is int ? map['total_rooms'] as int : 0,
    nextBatch: map['next_batch'] is int ? map['next_batch'] as int : null,
  );
}
