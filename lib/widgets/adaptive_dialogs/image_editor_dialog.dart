import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'image_editor_dialog_impl.dart' deferred as impl;

/// Eager stub. The real dialog lives in the deferred part above: it pulls in
/// google_fonts and the pro_image_editor chunk, which must stay out of the
/// web startup bundle until an image edit is actually requested.
Future<Uint8List?> showImageEditor({
  required BuildContext context,
  required Uint8List byteArray,
}) async {
  await impl.loadLibrary();
  return impl.showImageEditor(context: context, byteArray: byteArray);
}
