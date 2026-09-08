import 'package:flutter/material.dart';

void dismissKeyboard(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
}
