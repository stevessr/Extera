import 'package:cross_file/cross_file.dart';

/// Callback invoked when the browser reports that the drag state changed.
typedef WebDragStateCallback = void Function(bool isDragging);

/// Callback invoked with the files collected from a browser `drop` event.
typedef WebDropFilesCallback = void Function(List<XFile> files);

/// Registers listeners for browser drag-and-drop events.
///
/// Returns a dispose callback, or `null` on platforms without a browser DOM
/// (everything but web). On web the returned callback removes the registered
/// DOM event listeners.
void Function()? registerWebDropListener({
  required WebDragStateCallback onDragStateChanged,
  required WebDropFilesCallback onDrop,
}) => null;
