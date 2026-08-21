import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

/// Counter to distinguish genuine drag-leave from bubbling across child
/// elements. The desktop_drop web plugin uses DOM0
/// ``window.ondragleave`` which fires whenever the pointer crosses *any*
/// child element, not just when leaving the window. A counter correctly
/// detects the real leave (counter reaches 0).
int _dragCounter = 0;

/// Callbacks set by the current chat controller.
void Function(bool)? _onDragStateChanged;
void Function(List<XFile>)? _onDrop;

/// JS interop event listeners (kept so they can be removed).
JSFunction? _onDragEnter;
JSFunction? _onDragOver;
JSFunction? _onDragLeave;
JSFunction? _onDropHandler;

void registerWebDrop({
  required void Function(bool dragging) onDragStateChanged,
  required void Function(List<XFile> files) onDrop,
}) {
  _onDragStateChanged = onDragStateChanged;
  _onDrop = onDrop;

  _onDragEnter = (() {
    _dragCounter++;
    if (_dragCounter == 1) _onDragStateChanged?.call(true);
  }).toJS;

  _onDragOver = ((web.Event event) {
    // Calling preventDefault on dragover is required so that the
    // subsequent drop event fires.
    event.preventDefault();
  }).toJS;

  _onDragLeave = (() {
    _dragCounter--;
    if (_dragCounter <= 0) {
      _dragCounter = 0;
      _onDragStateChanged?.call(false);
    }
  }).toJS;

  _onDropHandler = ((web.DragEvent event) {
    event.preventDefault();
    _dragCounter = 0;
    _onDragStateChanged?.call(false);

    final dt = event.dataTransfer;
    if (dt == null) return;
    final files = dt.files;
    if (files.length == 0) return;

    final xfiles = <XFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;

      // Create a blob URL so XFile.readAsBytes() works via XMLHttpRequest,
      // which is the reliable path on web.
      final blob = web.Blob([file].toJS, web.BlobPropertyBag(type: file.type));
      final url = web.URL.createObjectURL(blob);

      xfiles.add(
        XFile(
          url,
          name: file.name,
          mimeType: file.type.isEmpty ? null : file.type,
          length: file.size,
        ),
      );
    }

    if (xfiles.isNotEmpty) _onDrop?.call(xfiles);
  }).toJS;

  final window = web.window;
  window.addEventListener('dragenter', _onDragEnter);
  window.addEventListener('dragover', _onDragOver);
  window.addEventListener('dragleave', _onDragLeave);
  window.addEventListener('drop', _onDropHandler);
}

void unregisterWebDrop() {
  final window = web.window;
  if (_onDragEnter != null) {
    window.removeEventListener('dragenter', _onDragEnter);
    _onDragEnter = null;
  }
  if (_onDragOver != null) {
    window.removeEventListener('dragover', _onDragOver);
    _onDragOver = null;
  }
  if (_onDragLeave != null) {
    window.removeEventListener('dragleave', _onDragLeave);
    _onDragLeave = null;
  }
  if (_onDropHandler != null) {
    window.removeEventListener('drop', _onDropHandler);
    _onDropHandler = null;
  }
  _onDragStateChanged = null;
  _onDrop = null;
  _dragCounter = 0;
}
