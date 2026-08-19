// Regenerates lib/config/animated_emoji_data.dart from Google's metadata.
//
// Usage: dart run tool/generate_animated_emoji.dart

import 'dart:convert';
import 'dart:io';

const _apiUrl =
    'https://googlefonts.github.io/noto-emoji-animation/data/api.json';
const _output = 'lib/config/animated_emoji_data.dart';

Future<void> main() async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(_apiUrl));
  final response = await request.close();
  if (response.statusCode != 200) {
    stderr.writeln('Failed to fetch $_apiUrl: HTTP ${response.statusCode}');
    exitCode = 1;
    return;
  }
  final body =
      jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  client.close();

  final codepoints =
      (body['icons'] as List)
          .map((icon) => (icon as Map<String, dynamic>)['codepoint'] as String)
          .toSet()
          .toList()
        ..sort();

  final buffer = StringBuffer();
  var line = '  ';
  for (final codepoint in codepoints) {
    final item = "'$codepoint',";
    if (line.length + item.length > 78) {
      buffer.writeln(line.trimRight());
      line = '  ';
    }
    line += '$item ';
  }
  buffer.write(line.trimRight());

  File(_output).writeAsStringSync('''
// GENERATED FILE - DO NOT EDIT BY HAND.
//
// The codepoint sequences Google ships an animated emoji for, taken from
// $_apiUrl
//
// Regenerate with: dart run tool/generate_animated_emoji.dart

/// Codepoints of every emoji available at
/// `https://fonts.gstatic.com/s/e/notoemoji/latest/<codepoint>/512.webp`,
/// lowercase hex joined by `_`.
const Set<String> kAnimatedEmojiCodepoints = {
$buffer
};
''');

  stdout.writeln('Wrote ${codepoints.length} codepoints to $_output');
}
