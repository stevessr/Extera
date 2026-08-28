import 'package:flutter/rendering.dart';

class MultiHoleClipper extends CustomClipper<Path> {
  final List<Rect> holes;

  const MultiHoleClipper({required this.holes});

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final hole in holes) {
      path.addRect(hole);
    }

    path.fillType = .evenOdd;

    return path;
  }

  @override
  bool shouldReclip(MultiHoleClipper oldClipper) {
    if (holes.length != oldClipper.holes.length) return true;
    for (var i = 0; i < holes.length; i++) {
      if (holes[i] != oldClipper.holes[i]) return true;
    }
    return false;
  }
}
