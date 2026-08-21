import 'package:cross_file/cross_file.dart';

/// No-op on non-web platforms.
void registerWebDrop({
  required void Function(bool dragging) onDragStateChanged,
  required void Function(List<XFile> files) onDrop,
}) {}

void unregisterWebDrop() {}
