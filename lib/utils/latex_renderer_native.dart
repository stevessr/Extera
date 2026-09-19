import 'package:latext/latext.dart';
import 'package:material_ui/material_ui.dart';

// Matrix's data-mx-maths attribute already tells us that the whole payload is
// TeX. LaTexT is designed for mixed text + math and otherwise parses `$` and
// the literal `\n` sequence itself. Its default break delimiter can therefore
// split valid commands such as `\nabla`, while dollar-based parsing can
// mis-detect formulas containing escaped dollars or more complex TeX.
//
// Feed LaTexT opaque private-use delimiters instead. They are only an adapter
// around the package's mixed-content API; the original TeX reaches Math.tex
// unchanged as one expression, including real newlines and `\\` row breaks.
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

/// Native builds compile deferred libraries in eagerly: nothing to load and
/// LaTexT renders synchronously, which is required because LatexSpan sits
/// inside a WidgetSpan — swapping a raw Text placeholder for a nested
/// rich-text layout on the next frame breaks Android line metrics.
Future<void> ensureLatexRendererLoaded() async {}

Widget buildLatexWidget({
  required Text laTeXCode,
  required dynamic Function(String) onErrorFallback,
}) => LaTexT(
  laTeXCode: _opaqueDelimitedLatex(laTeXCode),
  delimiter: _mathDelimiter,
  displayDelimiter: _displayDelimiter,
  breakDelimiter: _breakDelimiter,
  onErrorFallback: onErrorFallback,
);
