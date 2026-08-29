import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_avif/flutter_avif.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DynamicEmojiFormat {
  avif('AVIF', 'avif', 'image/avif'),
  gif('GIF', 'gif', 'image/gif'),
  apng('APNG', 'png', 'image/apng');

  final String label;
  final String extension;
  final String mimeType;

  const DynamicEmojiFormat(this.label, this.extension, this.mimeType);
}

abstract class DynamicEmojiPreferences {
  static const _key = 'xyz.extera.dynamicEmojiFormat';

  static Future<DynamicEmojiFormat> load() async {
    final store = await SharedPreferences.getInstance();
    final value = store.getString(_key);
    return DynamicEmojiFormat.values.firstWhere(
      (format) => format.name == value,
      orElse: () => DynamicEmojiFormat.avif,
    );
  }

  static Future<void> save(DynamicEmojiFormat format) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(_key, format.name);
  }
}

Future<void> sendDynamicEmoji({
  required Room room,
  required String source,
  required String name,
  required DynamicEmojiFormat format,
  Event? replyEvent,
  Thread? thread,
}) async {
  final sourceUri = Uri.parse(source);
  final isMatrixMedia = sourceUri.scheme == 'mxc';
  final downloadUri = isMatrixMedia
      ? await sourceUri.getDownloadUri(room.client)
      : sourceUri;
  final accessToken = room.client.accessToken;
  final response = await http.get(
    downloadUri,
    headers: isMatrixMedia && accessToken != null
        ? {'authorization': 'Bearer $accessToken'}
        : null,
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
      'Unable to download dynamic emoji (${response.statusCode})',
    );
  }

  final bytes = await _transcodeDynamicEmoji(response.bodyBytes, format);
  final file = MatrixImageFile(
    bytes: bytes,
    name: '$name.${format.extension}',
    mimeType: format.mimeType,
  );

  final extraContent = <String, dynamic>{
    'body': name,
    'info': <String, dynamic>{
      'mimetype': format.mimeType,
      'size': bytes.length,
    },
  };
  if (replyEvent != null) {
    extraContent['m.relates_to'] = {
      'm.in_reply_to': {'event_id': replyEvent.eventId},
    };
  }

  await room.sendFileEvent(
    file,
    extraContent: extraContent,
    threadLastEventId: thread?.lastEvent?.eventId ?? thread?.rootEvent.eventId,
    threadRootEventId: thread?.rootEvent.eventId,
  );
}

Future<Uint8List> _transcodeDynamicEmoji(
  Uint8List input,
  DynamicEmojiFormat format,
) async {
  if (format == DynamicEmojiFormat.avif) {
    // flutter_avif decodes every frame through Flutter's image codec before
    // encoding, so GIF/APNG/WebP animations keep their frame sequence.
    return encodeAvif(input);
  }

  final decoded = await _decodeAnimation(input);
  if (format == DynamicEmojiFormat.gif) {
    return image.encodeGif(decoded, singleFrame: false);
  }
  return image.encodePng(decoded, singleFrame: false);
}

Future<image.Image> _decodeAnimation(Uint8List input) async {
  // Decoder.decode(frame: null) retains the complete animation. Use the
  // explicit decoder rather than decodeImage so the multi-frame behaviour is
  // obvious and stays independent from convenience-function semantics.
  final decoder = image.findDecoderForData(input);
  final decoded = decoder?.decode(input);
  if (decoded != null) return decoded;

  // package:image does not decode AVIF. This fallback lets an AVIF image-pack
  // emoji still be converted to GIF/APNG without dropping its animation.
  final avifFrames = await decodeAvif(input);
  if (avifFrames.isEmpty) {
    throw const FormatException('Unsupported dynamic emoji image format');
  }

  image.Image? animation;
  for (var index = 0; index < avifFrames.length; index++) {
    final avifFrame = avifFrames[index];
    final byteData = await avifFrame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw const FormatException('Unable to decode dynamic emoji frame');
    }
    final frame = image.Image.fromBytes(
      width: avifFrame.image.width,
      height: avifFrame.image.height,
      bytes: byteData.buffer,
      bytesOffset: byteData.offsetInBytes,
      numChannels: 4,
      order: image.ChannelOrder.rgba,
      frameDuration: avifFrame.duration.inMilliseconds,
      frameIndex: index,
      frameType: image.FrameType.animation,
    );
    avifFrame.image.dispose();

    if (animation == null) {
      animation = frame;
      animation.loopCount = 0;
      animation.frameType = image.FrameType.animation;
    } else {
      animation.addFrame(frame);
    }
  }

  return animation!;
}
