// SPDX-FileCopyrightText: 2026 Extera contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/custom_http_client.dart';

/// Exception carrying the Matrix `errcode` of a failed raw API call.
class MscApiException implements Exception {
  final int statusCode;
  final String? errcode;
  final String? error;

  MscApiException(this.statusCode, {this.errcode, this.error});

  /// The server does not know this endpoint (feature unsupported).
  bool get unrecognized =>
      statusCode == 404 &&
      (errcode == 'M_UNRECOGNIZED' || errcode == 'M_UNKNOWN');

  @override
  String toString() => 'MscApiException($statusCode, $errcode, $error)';
}

/// Minimal authenticated raw HTTP access to homeserver endpoints which are
/// not (yet) part of the pinned matrix dart sdk. Works on all platforms by
/// reusing [CustomHttpClient.createHTTPClient].
class MscHttp {
  final Client client;

  MscHttp(this.client);

  Uri _resolve(String path, Map<String, String>? query) {
    final baseUri = client.baseUri;
    if (baseUri == null) {
      throw StateError('Client is not logged in');
    }
    return baseUri.resolve(
      query == null || query.isEmpty
          ? path
          : '$path?${Uri(queryParameters: query).query}',
    );
  }

  Future<http.Response> _run(
    String method,
    String path,
    Map<String, String>? query, {
    Object? body,
  }) async {
    final token = client.bearerToken;
    if (token == null) {
      throw StateError('Client is not logged in');
    }
    final request = http.Request(method, _resolve(path, query))
      ..headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final response =
        await request.send().timeout(const Duration(seconds: 30));
    final responseBody = await response.stream.toBytes();
    final decoded = jsonDecode(
      utf8.decode(responseBody),
    );
    final json = decoded is Map<String, Object?> ? decoded : null;
    if (response.statusCode >= 400) {
      throw MscApiException(
        response.statusCode,
        errcode: json?['errcode'] as String?,
        error: json?['error'] as String?,
      );
    }
    return http.Response.bytes(
      responseBody,
      response.statusCode,
      headers: response.headers,
    );
  }

  /// GET and decode a JSON object.
  Future<Map<String, Object?>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _run('GET', path, query);
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  /// PUT a JSON body and decode the JSON response.
  Future<Map<String, Object?>> putJson(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _run('PUT', path, query, body: body);
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, Object?> ? decoded : {};
  }

  /// POST a JSON body and decode the JSON response.
  Future<Map<String, Object?>> postJson(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _run('POST', path, query, body: body);
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, Object?> ? decoded : {};
  }

  /// DELETE and decode a JSON response.
  Future<Map<String, Object?>> deleteJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _run('DELETE', path, query);
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, Object?> ? decoded : {};
  }
}
