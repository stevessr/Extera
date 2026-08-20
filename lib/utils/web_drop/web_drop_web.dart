import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

import 'web_drop_stub.dart' show WebDropFilesCallback, WebDragStateCallback;
export 'web_drop_stub.dart' show WebDropFilesCallback, WebDragStateCallback;

/// Registers listeners for browser drag-and-drop events.
///
/// The standard `dragleave` event fires spuriously whenever the pointer moves
/// between child elements (due to DOM event bubbling). A counter
/// (dragenter → +1, dragleave → −1) is used so that [onDragStateChanged] is
/// only toggled when the pointer truly enters or leaves the window.
///
/// On `drop`, files are read from `dataTransfer.files` and wrapped in [XFile]
/// objects backed by object URLs, avoiding the `webkitGetAsEntry`-based
/// serialisation that the `desktop_drop` package uses on web (which can drop
/// events silently when its `DropTarget` status-gating rejects the drop).
void Function()? registerWebDropListener({
  required WebDragStateCallback onDragStateChanged,
  required WebDropFilesCallback onDrop,
}) {
  var dragCounter = 0;

  void handleDragEnter(web.Event event) {
    event.preventDefault();
    dragCounter++;
    if (dragCounter == 1) {
      onDragStateChanged(true);
    }
  }

  void handleDragOver(web.Event event) {
    // preventDefault on dragover is required for the drop event to fire.
    event.preventDefault();
  }

  void handleDragLeave(web.Event event) {
    event.preventDefault();
    dragCounter--;
    if (dragCounter <= 0) {
      dragCounter = 0;
      onDragStateChanged(false);
    }
  }

  void handleDrop(web.Event event) {
    final dragEvent = event as web.DragEvent;
    dragEvent.preventDefault();
    dragCounter = 0;
    onDragStateChanged(false);

    final dt = dragEvent.dataTransfer;
    if (dt == null) return;
    final fileList = dt.files;
    if (fileList.length == 0) return;

    final xfiles = <XFile>[];
    for (var i = 0; i < fileList.length; i++) {
      final file = fileList.item(i);
      if (file == null) continue;
      final url = web.URL.createObjectURL(file);
      xfiles.add(
        XFile(
          url,
          name: file.name,
          length: file.size,
          mimeType: file.type.isEmpty ? null : file.type,
          lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        ),
      );
    }
    if (xfiles.isNotEmpty) onDrop(xfiles);
  }

  final enter = handleDragEnter.toJS;
  final over = handleDragOver.toJS;
  final leave = handleDragLeave.toJS;
  final drop = handleDrop.toJS;

  web.window.addEventListener('dragenter', enter);
  web.window.addEventListener('dragover', over);
  web.window.addEventListener('dragleave', leave);
  web.window.addEventListener('drop', drop);

  return () {
    web.window.removeEventListener('dragenter', enter);
    web.window.removeEventListener('dragover', over);
    web.window.removeEventListener('dragleave', leave);
    web.window.removeEventListener('drop', drop);
  };
}
