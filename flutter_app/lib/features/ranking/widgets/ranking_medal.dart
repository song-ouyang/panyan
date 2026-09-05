import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/wanpan_theme.dart';

class RankingMedal extends StatelessWidget {
  const RankingMedal({required this.rank, super.key});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = switch (rank) {
      1 => (const Color(0xFFFFCF53), const Color(0xFFD98A0F)),
      2 => (const Color(0xFFD2DEE1), const Color(0xFF809298)),
      3 => (const Color(0xFFE6B78E), const Color(0xFFAB7146)),
      _ => null,
    };
    return Semantics(
      label: '第$rank名',
      excludeSemantics: true,
      child: SizedBox(
        width: 32,
        height: 42,
        child: colors == null
            ? Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: WanpanColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : CustomPaint(
                painter: _MedalPainter(fill: colors.$1, outline: colors.$2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$rank',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: colors.$2,
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter({required this.fill, required this.outline});

  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 42);
    final stroke = Paint()
      ..color = outline
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final color = Paint()..color = fill;
    final ribbons = Path()
      ..moveTo(8, 26)
      ..lineTo(8, 39)
      ..lineTo(13, 35)
      ..lineTo(16, 39)
      ..lineTo(18, 27)
      ..moveTo(17, 27)
      ..lineTo(20, 39)
      ..lineTo(24, 35)
      ..lineTo(27, 38)
      ..lineTo(25, 25);
    canvas
      ..drawPath(ribbons, color)
      ..drawPath(ribbons, stroke);
    final petals = Path();
    for (var step = 0; step <= 96; step++) {
      final angle = step / 96 * math.pi * 2;
      final radius = 12.9 + 1.65 * math.cos(angle * 8);
      final x = 16 + math.cos(angle) * radius;
      final y = 16 + math.sin(angle) * radius;
      if (step == 0) {
        petals.moveTo(x, y);
      } else {
        petals.lineTo(x, y);
      }
    }
    petals.close();
    canvas
      ..drawPath(petals, color)
      ..drawPath(petals, stroke)
      ..drawCircle(const Offset(16, 16), 9.2, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MedalPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.outline != outline;
}
