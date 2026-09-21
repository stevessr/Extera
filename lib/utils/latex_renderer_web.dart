import 'package:material_ui/material_ui.dart';

import 'package:latext/latext.dart' deferred as latext;

Future<void>? _loaded;

// Matrix's data-mx-maths attribute already identifies the complete payload as
// TeX. Avoid LaTexT's mixed-content `$` parser and its default literal `\n`
// break delimiter: the latter can split valid commands such as `\nabla`.
// Private-use delimiters keep real newlines, `\\` row breaks, escaped dollars,
// and nested TeX intact until flutter_math_fork parses the expression.
const String _mathDelimiter = '\uE000';
const String _displayDelimiter = '\uE001';
const String _breakDelimiter = '\uE002';

Text _opaqueDelimitedLatex(Text laTeXCode) {
  final source = laTeXCode.data ?? '';
  final math =
      source.length >= 2 && source.startsWith(r'$') && source.endsWith(r'$')
      ? source.substring(1, source.length - 1)
      : source;

  return Text(
    '${_mathDelimiter}$math${_mathDelimiter}',
    style: laTeXCode.style,
    textAlign: laTeXCode.textAlign,
    textDirection: laTeXCode.textDirection,
    locale: laTeXCode.locale,
    softWrap: laTeXCode.softWrap,
    overflow: laTeXCode.overflow,
    maxLines: laTeXCode.maxLines,
    semanticsLabel: laTeXCode.semanticsLabel,
  );
}

/// The renderer (latext + flutter_math_fork, ~1 MB of Dart source) stays out
/// of the web startup bundle; load it on the first LaTeX span.
Future<void> ensureLatexRendererLoaded() => _loaded ??= latext.loadLibrary();

Widget buildLatexWidget({
  required Text laTeXCode,
  required dynamic Function(String) onErrorFallback,
}) => latext.LaTexT(
  laTeXCode: _opaqueDelimitedLatex(laTeXCode),
  delimiter: _mathDelimiter,
  displayDelimiter: _displayDelimiter,
  breakDelimiter: _breakDelimiter,
  onErrorFallback: onErrorFallback,
);
