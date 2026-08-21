import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:extera_next/widgets/mxc_image.dart';

/// An [http.Client] stub with three modes, selected by [failuresLeft]:
///   > 0 : the first N GETs throw the web transport error
///         (`http.ClientException: Failed to fetch`), then recover;
///   = 0 : immediate success with [successBody];
///   < 0 : every GET throws a plain Exception (HTTP-level permanent
///         failure), never recovering.
/// Non-media endpoints (e.g. the well-known probe the SDK fires) always get
/// a boring 404 so they stay out of the way.
class FlakyHttpClient implements http.Client {
  int failuresLeft;
  final Uint8List successBody;

  FlakyHttpClient({required this.failuresLeft, required this.successBody});

  http.Response _respond(Uri url) {
    if (url.path.endsWith('/client/versions')) {
      // Client.authenticatedMediaSupported probes this; advertise v1.11 so
      // the SDK uses the authenticated media endpoints.
      return http.Response(
        '{"versions":["v1.1","v1.11"]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (!url.path.contains('/media/')) {
      return http.Response(
        '{"errcode":"M_UNRECOGNIZED","error":"unhandled by test stub"}',
        404,
        headers: {'content-type': 'application/json'},
      );
    }
    if (failuresLeft > 0) {
      failuresLeft--;
      throw http.ClientException('Failed to fetch', url);
    }
    if (failuresLeft < 0) {
      throw Exception('Failed to download: 404 $url');
    }
    return http.Response.bytes(
      successBody,
      200,
      headers: {'content-type': 'image/png'},
    );
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      _respond(url);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = _respond(request.url);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      contentLength: response.bodyBytes.length,
      headers: response.headers,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Regression guard for the wasm crash on failed media downloads: a web
/// transport failure surfaces as package:http's `ClientException`, which
/// implements Exception but NOT IOException. `_tryLoad` used to catch only
/// IOException, so the error escaped as an unhandled async exception and
/// crashed dart2wasm apps. See `lib/widgets/mxc_image.dart`.
void main() {
  late MatrixSdkDatabase database;
  late Client client;

  setUpAll(() async {
    sqfliteFfiInit();
    database = await MatrixSdkDatabase.init(
      'mxc_image_error_test_${DateTime.now().microsecondsSinceEpoch}',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('mxc_image_error_test', database: database);
    client.homeserver = Uri.parse('https://example.org');
  });

  tearDownAll(() => database.delete());

  // 1x1 transparent PNG.
  final png = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  Future<void> pumpImage(WidgetTester tester, Uri mxc) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MxcImage(
          uri: mxc,
          client: client,
          retryDuration: const Duration(milliseconds: 1),
        ),
      ),
    );
  }

  AnimatedCrossFade fadeState(WidgetTester tester) =>
      tester.widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade));

  testWidgets('recovers after a transport ClientException', (tester) async {
    final flaky = FlakyHttpClient(failuresLeft: 1, successBody: png);
    client.httpClient = flaky;

    await pumpImage(tester, Uri.parse('mxc://example.org/flaky-image'));

    // First attempt fails inside the post-frame callback; the retry timer
    // gets scheduled. Neither may escape as an unhandled async error.
    await tester.pump();
    expect(fadeState(tester).crossFadeState, CrossFadeState.showSecond);

    // Transport recovers before the retry fires.
    flaky.failuresLeft = 0;
    await tester.pump(const Duration(milliseconds: 10));

    expect(
      fadeState(tester).crossFadeState,
      CrossFadeState.showFirst,
      reason: 'image must render once the transport recovers',
    );
  });

  testWidgets('gives up quietly on permanent (non-IO) failures', (
    tester,
  ) async {
    // Plain Exception("Failed to download: 404 ...") is not an IOException;
    // it must be logged and dropped, not retried forever nor rethrown.
    client.httpClient = FlakyHttpClient(failuresLeft: -100, successBody: png);

    await pumpImage(tester, Uri.parse('mxc://example.org/dead-image'));

    // Flush every scheduled retry; the widget must settle with no pending
    // timers and no unhandled errors.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(fadeState(tester).crossFadeState, CrossFadeState.showSecond);
  });
}
