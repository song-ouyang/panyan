import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';

/// The original black cat, drawn compactly for an avatar corner or a notice.
/// It stays still unless the surrounding user-triggered component moves it.
class WanpanCatMark extends StatelessWidget {
  const WanpanCatMark({super.key, this.size = 34, this.peeking = false});

  final double size;
  final bool peeking;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _CatPainter(peeking: peeking),
      ),
    ),
  );
}

class _CatPainter extends CustomPainter {
  const _CatPainter({required this.peeking});

  final bool peeking;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final fill = Paint()..color = WanpanColors.catBlack;
    final head = Path()
      ..moveTo(5, 16)
      ..lineTo(3.8, 5.3)
      ..quadraticBezierTo(3.5, 2.5, 5.9, 3.5)
      ..lineTo(13.1, 8)
      ..quadraticBezierTo(20, 5.9, 26.9, 8)
      ..lineTo(34.1, 3.5)
      ..quadraticBezierTo(36.5, 2.5, 36.2, 5.3)
      ..lineTo(35, 16)
      ..cubicTo(38, 28, 31.4, 35, 20, 35)
      ..cubicTo(8.6, 35, 2, 28, 5, 16)
      ..close();
    canvas.drawPath(head, fill);
    final eyes = Paint()..color = WanpanColors.surface;
    canvas
      ..drawCircle(const Offset(12.8, 18.6), 6.25, eyes)
      ..drawCircle(const Offset(27.2, 18.6), 6.25, eyes)
      ..drawCircle(const Offset(13.5, 19.2), 2.7, fill)
      ..drawCircle(const Offset(26.5, 19.2), 2.7, fill);
    final whiskers = Paint()
      ..color = WanpanColors.surface
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(3.5, 25), const Offset(8.4, 26), whiskers)
      ..drawLine(const Offset(3.9, 28.8), const Offset(8.4, 28.4), whiskers)
      ..drawLine(const Offset(31.6, 26), const Offset(36.5, 25), whiskers)
      ..drawLine(const Offset(31.6, 28.4), const Offset(36.1, 28.8), whiskers);
    final mouth = Path()
      ..moveTo(17.1, 27.3)
      ..quadraticBezierTo(20, 28.4, 22.9, 27.3)
      ..quadraticBezierTo(22.2, 31.4, 20, 31.4)
      ..quadraticBezierTo(17.8, 31.4, 17.1, 27.3);
    canvas.drawPath(mouth, Paint()..color = WanpanColors.coral);
    if (peeking) {
      for (final x in [8.4, 31.6]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, 34.2), width: 9.8, height: 10.8),
          fill,
        );
        final pawLine = Paint()
          ..color = WanpanColors.inkSecondary.withValues(alpha: .65)
          ..strokeWidth = .65
          ..strokeCap = StrokeCap.round;
        canvas
          ..drawLine(Offset(x - 1.8, 35.8), Offset(x - 1.8, 38), pawLine)
          ..drawLine(Offset(x + 1.4, 35.8), Offset(x + 1.4, 38), pawLine);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CatPainter oldDelegate) => oldDelegate.peeking != peeking;
}
