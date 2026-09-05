import 'package:flutter/material.dart';

import '../../../app/wanpan_theme.dart';

/// A quiet corner of the climbing wall, positioned behind the ranking content.
/// The caller places it in a Stack so it never takes space from the list.
class RankingRockBackdrop extends StatelessWidget {
  const RankingRockBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: 260,
          height: 150,
          child: CustomPaint(painter: _RankingRockPainter()),
        ),
      ),
    ),
  );
}

class _RankingRockPainter extends CustomPainter {
  const _RankingRockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 260, size.height / 150);
    final edge = Path()
      ..moveTo(0, 150)
      ..cubicTo(34, 145, 48, 117, 76, 109)
      ..cubicTo(99, 102, 106, 116, 126, 105)
      ..cubicTo(144, 95, 142, 73, 161, 68)
      ..cubicTo(181, 62, 194, 68, 204, 45)
      ..cubicTo(215, 20, 236, 8, 260, 5);
    final wall = Path.from(edge)
      ..lineTo(260, 150)
      ..close();
    canvas
      ..drawPath(wall, Paint()..color = WanpanColors.surfaceSoft)
      ..drawPath(
        edge,
        Paint()
          ..color = WanpanColors.borderStrong.withValues(alpha: .8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      );
    final grain = Paint()..color = WanpanColors.border.withValues(alpha: .7);
    for (final (point, radius) in const [
      (Offset(57, 135), 2.2),
      (Offset(81, 121), 1.8),
      (Offset(104, 143), 2.8),
      (Offset(156, 126), 2.1),
      (Offset(168, 91), 1.8),
      (Offset(187, 111), 2.6),
      (Offset(234, 38), 2.2),
      (Offset(246, 96), 1.7),
    ]) {
      canvas.drawCircle(point, radius, grain);
    }
    canvas.drawPath(
      Path()
        ..moveTo(174, 144)
        ..quadraticBezierTo(168, 137, 175, 135)
        ..quadraticBezierTo(183, 136, 183, 143)
        ..quadraticBezierTo(179, 147, 174, 144),
      Paint()
        ..color = WanpanColors.border.withValues(alpha: .75)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    _paintLeaves(canvas);
    _paintHold(
      canvas,
      center: const Offset(128, 123),
      color: WanpanColors.grape,
      depth: const Color(0xFF7254AE),
      rotation: -.28,
      scale: .78,
    );
    _paintHold(
      canvas,
      center: const Offset(216, 78),
      color: WanpanColors.coral,
      depth: WanpanColors.coralStrong,
      rotation: .32,
      scale: 1,
    );
    canvas.restore();
  }

  void _paintHold(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required Color depth,
    required double rotation,
    required double scale,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.scale(scale);
    final hold = Path()
      ..moveTo(-23, 5)
      ..cubicTo(-24, -6, -8, -20, 6, -18)
      ..cubicTo(20, -17, 26, -8, 22, 6)
      ..cubicTo(18, 19, -19, 23, -23, 5)
      ..close();
    canvas
      ..drawPath(hold.shift(const Offset(0, 3)), Paint()..color = depth)
      ..drawPath(hold, Paint()..color = color)
      ..drawPath(
        hold,
        Paint()
          ..color = WanpanColors.ink.withValues(alpha: .82)
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    canvas.drawPath(
      Path()
        ..moveTo(-16, -1)
        ..quadraticBezierTo(-12, -10, -4, -12),
      Paint()
        ..color = WanpanColors.surface.withValues(alpha: .42)
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas
      ..drawCircle(const Offset(1, 1), 4.4, Paint()..color = depth)
      ..drawCircle(
        const Offset(1, 1),
        3.1,
        Paint()..color = WanpanColors.catBlack,
      )
      ..drawCircle(
        const Offset(1.6, .4),
        1.05,
        Paint()..color = color.withValues(alpha: .8),
      );
    canvas.restore();
  }

  void _paintLeaves(Canvas canvas) {
    const sage = Color(0xFF96AB80);
    const sageDark = Color(0xFF748A62);
    final stem = Path()
      ..moveTo(239, 149)
      ..quadraticBezierTo(231, 126, 228, 111);
    final leftLeaf = Path()
      ..moveTo(235, 139)
      ..cubicTo(220, 138, 211, 124, 213, 116)
      ..cubicTo(225, 119, 233, 126, 235, 139)
      ..close();
    final rightLeaf = Path()
      ..moveTo(237, 143)
      ..cubicTo(237, 128, 247, 115, 255, 113)
      ..cubicTo(257, 128, 251, 139, 237, 143)
      ..close();
    final topLeaf = Path()
      ..moveTo(230, 122)
      ..cubicTo(219, 113, 220, 102, 225, 95)
      ..cubicTo(235, 102, 235, 112, 230, 122)
      ..close();
    canvas
      ..drawPath(rightLeaf, Paint()..color = sageDark)
      ..drawPath(leftLeaf, Paint()..color = sage)
      ..drawPath(topLeaf, Paint()..color = sage)
      ..drawPath(
        stem,
        Paint()
          ..color = sageDark
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
  }

  @override
  bool shouldRepaint(_RankingRockPainter oldDelegate) => false;
}
