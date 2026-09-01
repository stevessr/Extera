import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:matrix/matrix.dart';

final _inFlightMxcDownloads = <String, Future<Uint8List>>{};

Uint8List _deriveRoundedImage(Uint8List imageData, {required bool rounded}) {
  if (!rounded) return imageData;
  final image = decodeImage(imageData);
  return image == null ? imageData : encodePng(copyCropCircle(image));
}

class MxcDownloadException implements Exception {
  final int statusCode;
  final Uri uri;
  final String responseBody;

  const MxcDownloadException({
    required this.statusCode,
    required this.uri,
    required this.responseBody,
  });

  bool get isRetryable =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  @override
  String toString() =>
      'MxcDownloadException(statusCode: $statusCode, uri: $uri)';
}

extension ClientDownloadContentExtension on Client {
  Future<Uint8List> downloadMxcCached(
    Uri mxc, {
    num? width = 128,
    num? height = 128,
    bool isThumbnail = false,
    bool? animated,
    ThumbnailMethod? thumbnailMethod,
    bool rounded = false,
  }) async {
    final effectiveThumbnailMethod = thumbnailMethod ?? ThumbnailMethod.scale;

    // To stay compatible with previous storeKeys:
    final cacheKey = isThumbnail
        // ignore: deprecated_member_use
        ? mxc.getThumbnail(
            this,
            width: width,
            height: height,
            animated: animated,
            method: effectiveThumbnailMethod,
          )
        : mxc;

    // The same sticker can be visible in favourites, recents and its source
    // pack at once. Coalesce identical cache/network work so those widgets do
    // not race each other into duplicate database reads or HTTP requests. Keep
    // requests client-scoped because authenticated media access can differ
    // between accounts even when the MXC URI is identical.
    final inFlightKey = '${identityHashCode(this)}|$cacheKey|rounded=$rounded';
    final pending = _inFlightMxcDownloads[inFlightKey];
    if (pending != null) return pending;

    final future = () async {
      final cachedData = await database.getFile(cacheKey);
      if (cachedData != null) {
        return _deriveRoundedImage(cachedData, rounded: rounded);
      }

      final httpUri = isThumbnail
          ? await mxc.getThumbnailUri(
              this,
              width: width,
              height: height,
              animated: animated,
              method: effectiveThumbnailMethod,
            )
          : await mxc.getDownloadUri(this);

      final response = await httpClient.get(
        httpUri,
        headers: accessToken == null
            ? null
            : {'authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) {
        throw MxcDownloadException(
          statusCode: response.statusCode,
          uri: httpUri,
          responseBody: response.body,
        );
      }
      final imageData = response.bodyBytes;

      // Persist only the canonical media bytes. `rounded` is a presentation
      // variant used by notification avatars; caching the derived PNG under
      // the normal MXC key would make rounded and non-rounded callers corrupt
      // each other's cache results.
      await database.storeFile(cacheKey, imageData, 0);

      return _deriveRoundedImage(imageData, rounded: rounded);
    }();

    _inFlightMxcDownloads[inFlightKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightMxcDownloads[inFlightKey], future)) {
        _inFlightMxcDownloads.remove(inFlightKey);
      }
    }
  }
}
