import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';

/// A small, static version of the diary's black cat for transient feedback.
class WanpanCatMark extends StatelessWidget {
  const WanpanCatMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(size: Size.square(size), painter: const _CatPainter()),
    ),
  );
}

class _CatPainter extends CustomPainter {
  const _CatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 36, size.height / 36);
    final fill = Paint()..color = WanpanColors.catBlack;
    final head = Path()
      ..moveTo(5, 14)
      ..lineTo(3.5, 4)
      ..quadraticBezierTo(3.3, 2, 5.2, 3.1)
      ..lineTo(12, 7.5)
      ..quadraticBezierTo(18, 5, 24, 7.5)
      ..lineTo(30.8, 3.1)
      ..quadraticBezierTo(32.7, 2, 32.5, 4)
      ..lineTo(31, 14)
      ..cubicTo(33, 25, 28, 32, 18, 32)
      ..cubicTo(8, 32, 3, 25, 5, 14)
      ..close();
    canvas.drawPath(head, fill);
    final eyes = Paint()..color = WanpanColors.surface;
    canvas
      ..drawCircle(const Offset(11.7, 17), 5.4, eyes)
      ..drawCircle(const Offset(24.3, 17), 5.4, eyes)
      ..drawCircle(const Offset(12.3, 17.6), 2.7, fill)
      ..drawCircle(const Offset(23.7, 17.6), 2.7, fill);
    final whiskers = Paint()
      ..color = WanpanColors.surface
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(4.8, 23), const Offset(8.4, 24), whiskers)
      ..drawLine(const Offset(4.8, 26), const Offset(8.4, 26.4), whiskers)
      ..drawLine(const Offset(27.6, 24), const Offset(31.2, 23), whiskers)
      ..drawLine(const Offset(27.6, 26.4), const Offset(31.2, 26), whiskers);
    final mouth = Path()
      ..moveTo(15.2, 25)
      ..quadraticBezierTo(18, 26.2, 20.8, 25)
      ..quadraticBezierTo(19.8, 29.2, 18, 28.4)
      ..quadraticBezierTo(16.2, 29.2, 15.2, 25);
    canvas.drawPath(mouth, Paint()..color = WanpanColors.coral);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CatPainter oldDelegate) => false;
}
