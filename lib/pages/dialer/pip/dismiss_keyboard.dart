import 'package:material_ui/material_ui.dart';

void dismissKeyboard(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
}
