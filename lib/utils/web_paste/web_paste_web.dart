import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_paste_stub.dart' show WebPasteImageCallback;

export 'web_paste_stub.dart' show WebPasteImageCallback;

/// Registers a listener for the browser `paste` event.
///
/// Plain text keeps its default behaviour (the browser pastes it into the
/// focused input). Images are intercepted, read into memory and handed to
/// [onImage] so that they can be uploaded as an attachment instead.
void Function()? registerWebPasteListener(WebPasteImageCallback onImage) {
  void handlePaste(web.Event event) {
    final clipboardData = (event as web.ClipboardEvent).clipboardData;
    if (clipboardData == null) return;

    final items = clipboardData.items;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind != 'file') continue;

      final mimeType = item.type;
      if (!mimeType.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file == null) continue;

      // Only swallow the event once we know we are handling an image, so
      // that pasting text into the input bar keeps working.
      event.preventDefault();
      file.arrayBuffer().toDart.then((buffer) {
        onImage(buffer.toDart.asUint8List(), mimeType);
      });
      return;
    }
  }

  final listener = handlePaste.toJS;
  web.window.addEventListener('paste', listener);
  return () => web.window.removeEventListener('paste', listener);
}
