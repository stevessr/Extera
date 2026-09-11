import 'package:flutter/rendering.dart';

class MultiHoleClipper extends CustomClipper<Path> {
  final List<Rect> holes;
  final Radius? radius;

  const MultiHoleClipper({required this.holes, this.radius});

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final hole in holes) {
      if (radius != null) {
        path.addRRect(RRect.fromRectAndRadius(hole, radius!));
      } else {
        path.addRect(hole);
      }
    }

    path.fillType = .evenOdd;

    return path;
  }

  @override
  bool shouldReclip(MultiHoleClipper oldClipper) {
    if (radius != oldClipper.radius) return true;
    if (holes.length != oldClipper.holes.length) return true;
    for (var i = 0; i < holes.length; i++) {
      if (holes[i] != oldClipper.holes[i]) return true;
    }
    return false;
  }
}
