import 'package:flutter/material.dart';

import 'package:latext/latext.dart';

/// Native builds compile deferred libraries in eagerly: nothing to load and
/// LaTexT renders synchronously, which is required because LatexSpan sits
/// inside a WidgetSpan — swapping a raw Text placeholder for a nested
/// rich-text layout on the next frame breaks Android line metrics.
Future<void> ensureLatexRendererLoaded() async {}

Widget buildLatexWidget({
  required Text laTeXCode,
  required dynamic Function(String) onErrorFallback,
}) => LaTexT(laTeXCode: laTeXCode, onErrorFallback: onErrorFallback);
