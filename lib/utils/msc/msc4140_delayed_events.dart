// SPDX-FileCopyrightText: 2026 Extera contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/msc/msc_http.dart';

/// App-side complement to the SDK's MSC4140 support: the SDK covers
/// state-event delay, management and listing, but not delayed *message*
/// sends on the room send endpoint.
extension DelayedMessageSend on Client {
  /// Queues [content] in [room] to be sent after [delay].
  /// Returns the server-issued delay ID.
  ///
  /// Encrypted rooms are handled transparently: the payload is encrypted
  /// with `encryptGroupMessagePayload` and sent as an m.room.encrypted
  /// event (the encryption helper re-attaches thread/reply relations).
  Future<String> sendDelayedMessage({
    required Room room,
    required Map<String, Object?> content,
    required Duration delay,
    String type = EventTypes.Message,
  }) async {
    var eventType = type;
    var payload = content;
    final encryption = room.client.encryption;
    if (room.encrypted && encryption != null) {
      payload = await encryption.encryptGroupMessagePayload(
        room.id,
        content,
        type: type,
      );
      eventType = EventTypes.Encrypted;
    }
    final txid =
        '${DateTime.now().millisecondsSinceEpoch}'
        '${Random.secure().nextInt(99999)}';
    final http = MscHttp(this);
    final response = await http.putJson(
      '_matrix/client/v3/rooms/${Uri.encodeComponent(room.id)}'
      '/send/${Uri.encodeComponent(eventType)}/$txid',
      query: {'org.matrix.msc4140.delay': delay.inMilliseconds.toString()},
      body: payload,
    );
    final delayId = response['delay_id'];
    if (delayId is! String) {
      throw MscApiException(
        200,
        errcode: 'M_INVALID_RESPONSE',
        error: 'Missing delay_id in response',
      );
    }
    return delayId;
  }

  /// Lists pending delayed events of [roomId]; empty when the server
  /// does not expose MSC4140.
  Future<List<ScheduledDelayedEvent>> listDelayedEvents(String roomId) async {
    try {
      final response = await getScheduledDelayedEvents();
      return response.scheduledEvents
          .where((event) => event.roomId == roomId)
          .toList();
    } on MatrixException catch (e) {
      final errcode = e.errcode;
      if (errcode == 'M_UNRECOGNIZED' || errcode == 'M_UNKNOWN') {
        return const [];
      }
      rethrow;
    }
  }
}

extension ScheduledDelayedEventX on ScheduledDelayedEvent {
  /// Best-effort estimate of the remaining time until the homeserver
  /// sends this event.
  Duration parseRemaining() {
    final elapsed = DateTime.now().millisecondsSinceEpoch - runningSince;
    final remainingMs = delay - elapsed;
    return Duration(milliseconds: remainingMs <= 0 ? 0 : remainingMs);
  }

  String? get bodyPreview {
    final body = content['body'];
    return body is String ? body : null;
  }
}
