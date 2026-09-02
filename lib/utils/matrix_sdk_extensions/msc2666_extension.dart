import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix.dart' as matrix;

const _msc2666Feature = 'uk.half-shot.msc2666.query_mutual_rooms';
const _msc2666StableFeature = 'uk.half-shot.msc2666.query_mutual_rooms.stable';

/// Whether the homeserver advertises a specification version which contains
/// the stable Mutual Rooms API, or the transitional stable feature flag used
/// before Matrix v1.19 was released.
bool supportsStableMutualRooms(matrix.GetVersionsResponse versions) {
  if (versions.unstableFeatures?[_msc2666StableFeature] == true) return true;

  for (final version in versions.versions) {
    final match = RegExp(r'^v(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) continue;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    if (major > 1 || (major == 1 && minor >= 19)) return true;
  }
  return false;
}

extension Msc2666Extension on matrix.Client {
  Future<bool> isMsc2666Supported() async {
    final versions = await getVersions();
    return supportsStableMutualRooms(versions) ||
        versions.unstableFeatures?[_msc2666Feature] == true;
  }

  Future<bool> isMsc2666StableSupported() async =>
      supportsStableMutualRooms(await getVersions());

  Future<List<String>> queryMutualRoomsIds(String userId) async {
    final msc2666Stable = await isMsc2666StableSupported();
    if (baseUri == null) return [];

    final joined = <String>[];
    final seenPaginationTokens = <String>{};
    String? from;

    do {
      final requestUri = Uri(
        path: msc2666Stable
            ? '/_matrix/client/v1/mutual_rooms'
            : '/_matrix/client/unstable/uk.half-shot.msc2666/user/mutual_rooms',
        queryParameters: {
          'user_id': userId,
          if (msc2666Stable && from != null) 'from': from,
        },
      );

      final request = Request('GET', baseUri!.resolveUri(requestUri));
      request.headers['authorization'] = 'Bearer $accessToken';
      final response = await httpClient.send(request);
      final responseBody = await response.stream.toBytes();
      if (response.statusCode != 200) {
        unexpectedResponse(response, responseBody);
      }

      final responseString = utf8.decode(responseBody);
      final json = jsonDecode(responseString) as Map<String, dynamic>;
      final page = json['joined'];
      if (page is List) {
        joined.addAll(page.whereType<String>());
      }

      if (!msc2666Stable) break;
      final nextBatch = json['next_batch'];
      if (nextBatch is! String || nextBatch.isEmpty) break;
      if (!seenPaginationTokens.add(nextBatch)) break;
      from = nextBatch;
    } while (true);

    return joined;
  }
}
