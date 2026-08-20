import 'package:flutter/material.dart';

extension StringColor on String {
  static final _colorSchemeCache = <String, ColorScheme>{};

  ColorScheme get colorScheme =>
      _colorSchemeCache[this] ??= ColorScheme.fromSeed(
        seedColor: _getColorLight(0.3),
        dynamicSchemeVariant:
            .rainbow, // TODO: use dynamic scheme variant used across the app
      );

  Color _getColorLight(double light) {
    var number = 0.0;
    for (var i = 0; i < length; i++) {
      number += codeUnitAt(i);
    }
    number = (number % 12) * 25.5;
    return HSLColor.fromAHSL(0.75, number, 1, light).toColor();
  }
}
