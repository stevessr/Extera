import 'package:flutter/material.dart';

import 'package:latext/latext.dart' deferred as latext;

Future<void>? _loaded;

/// The renderer (latext + flutter_math_fork, ~1 MB of Dart source) stays out
/// of the web startup bundle; load it on the first LaTeX span.
Future<void> ensureLatexRendererLoaded() => _loaded ??= latext.loadLibrary();

Widget buildLatexWidget({
  required Text laTeXCode,
  required dynamic Function(String) onErrorFallback,
}) => latext.LaTexT(laTeXCode: laTeXCode, onErrorFallback: onErrorFallback);
