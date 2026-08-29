// Downloads the Lottie animation of every emoji in
// lib/config/animated_emoji_data.dart into assets/animated_emoji/.
//
// The animations are not checked into git; run this before building, or let
// the app fall back to downloading them at runtime.
//
// Usage: dart run tool/download_animated_emoji.dart

import 'dart:convert';
import 'dart:io';

import 'package:extera_next/config/animated_emoji_data.dart';

const _outputDirectory = 'assets/animated_emoji';
const _concurrency = 8;
const _attempts = 3;
const _timeout = Duration(seconds: 30);
const _knownUnavailable = {'ae_fe0f', 'a9_fe0f'};

/// Thrown when Google lists an emoji in its metadata but ships no animation
/// for it. Nothing we can do about those, the app falls back to the glyph.
class _NotAvailable implements Exception {}

String _url(String codepoint) =>
    'https://fonts.gstatic.com/s/e/notoemoji/latest/$codepoint/lottie.json';

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final directory = Directory(_outputDirectory);
  await directory.create(recursive: true);

  final pending = <String>[
    for (final codepoint in kAnimatedEmojiCodepoints)
      if (!_knownUnavailable.contains(codepoint) &&
          (force || !File('$_outputDirectory/$codepoint.json').existsSync()))
        codepoint,
  ];

  final skipped = kAnimatedEmojiCodepoints.length - pending.length;
  if (pending.isEmpty) {
    stdout.writeln('All $skipped animated emoji are already downloaded.');
    return;
  }
  stdout.writeln(
    'Downloading ${pending.length} animated emoji '
    '($skipped already present)...',
  );

  final client = HttpClient()..connectionTimeout = _timeout;
  final failed = <String>[];
  final unavailable = <String>[];
  var done = 0;

  Future<void> worker() async {
    while (pending.isNotEmpty) {
      final codepoint = pending.removeLast();
      Object? lastError;

      for (var attempt = 1; attempt <= _attempts; attempt++) {
        try {
          await _download(client, codepoint).timeout(_timeout);
          lastError = null;
          break;
        } on _NotAvailable {
          unavailable.add(codepoint);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (attempt < _attempts) {
            await Future.delayed(Duration(seconds: attempt));
          }
        }
      }

      if (lastError != null) {
        failed.add(codepoint);
        stderr.writeln('  $codepoint: $lastError');
      }
      done++;
      if (done % 100 == 0) stdout.writeln('  $done processed');
    }
  }

  await Future.wait(List.generate(_concurrency, (_) => worker()));
  client.close();

  if (unavailable.isNotEmpty) {
    stdout.writeln(
      'No animation published for ${unavailable.length} emoji: '
      '${unavailable.join(', ')}',
    );
  }
  if (failed.isNotEmpty) {
    stderr.writeln('Failed to download ${failed.length} emoji.');
    exitCode = 1;
    return;
  }
  stdout.writeln('Done. $_outputDirectory is up to date.');
}

Future<void> _download(HttpClient client, String codepoint) async {
  final request = await client.getUrl(Uri.parse(_url(codepoint)));
  final response = await request.close();
  if (response.statusCode == HttpStatus.notFound) {
    await response.drain<void>();
    throw _NotAvailable();
  }
  if (response.statusCode != 200) {
    await response.drain<void>();
    throw HttpException('HTTP ${response.statusCode}');
  }

  final body = await response.transform(utf8.decoder).join();
  // Guard against a CDN error page being written as if it were an animation.
  jsonDecode(body);

  // Write to a temporary file first so that an interrupted run cannot leave a
  // truncated animation behind, which the next run would happily skip.
  final target = File('$_outputDirectory/$codepoint.json');
  final temporary = File('${target.path}.part');
  await temporary.writeAsString(body, flush: true);
  await temporary.rename(target.path);
}
