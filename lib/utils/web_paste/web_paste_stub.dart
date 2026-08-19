import 'dart:typed_data';

/// Callback invoked with the raw bytes and mime type of a pasted image.
typedef WebPasteImageCallback = void Function(Uint8List bytes, String mimeType);

/// Registers a listener for the browser `paste` event.
///
/// Returns a dispose callback, or `null` on platforms without a browser
/// clipboard (everything but web).
void Function()? registerWebPasteListener(WebPasteImageCallback onImage) => null;
