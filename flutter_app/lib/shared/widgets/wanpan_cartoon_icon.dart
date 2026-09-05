import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';

enum WanpanCartoonIconKind {
  post,
  comment,
  favorite,
  like,
  route,
  friends,
  invite,
}

/// Small illustrated icons; the surrounding control owns its label and tap.
class WanpanCartoonIcon extends StatelessWidget {
  const WanpanCartoonIcon({required this.kind, this.size = 28, super.key});

  final WanpanCartoonIconKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _CartoonIconPainter(kind),
      ),
    ),
  );
}

class _CartoonIconPainter extends CustomPainter {
  const _CartoonIconPainter(this.kind);

  final WanpanCartoonIconKind kind;

  Paint get _outline => Paint()
    ..color = WanpanColors.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  Paint _fill(Color color) => Paint()..color = color;

  void _surface(Canvas canvas, Path path, Color color) {
    canvas
      ..drawPath(path, _fill(color))
      ..drawPath(path, _outline);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    switch (kind) {
      case WanpanCartoonIconKind.post:
        _post(canvas);
      case WanpanCartoonIconKind.comment:
        _comment(canvas);
      case WanpanCartoonIconKind.favorite:
        _favorite(canvas);
      case WanpanCartoonIconKind.like:
        _like(canvas);
      case WanpanCartoonIconKind.route:
        _route(canvas);
      case WanpanCartoonIconKind.friends:
        _friends(canvas);
      case WanpanCartoonIconKind.invite:
        _invite(canvas);
    }
    canvas.restore();
  }

  void _post(Canvas canvas) {
    final paper = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, 4, 25, 32),
      const Radius.circular(5),
    );
    canvas
      ..drawRRect(paper.shift(const Offset(0, 1.5)), _fill(WanpanColors.border))
      ..drawRRect(paper, _fill(WanpanColors.surface))
      ..drawRRect(paper, _outline);
    final line = Paint()
      ..color = WanpanColors.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final y in [13.0, 20.0, 27.0]) {
      canvas.drawLine(Offset(14, y), Offset(y == 27 ? 24 : 27, y), line);
    }
    canvas
      ..drawCircle(const Offset(32, 11), 4.5, _fill(WanpanColors.coral))
      ..drawCircle(const Offset(32, 11), 4.5, _outline);
  }

  void _comment(Canvas canvas) {
    final bubble = Path()
      ..moveTo(20, 5)
      ..cubicTo(9, 5, 4.5, 11, 5, 20)
      ..quadraticBezierTo(5.2, 27.4, 11.1, 30)
      ..lineTo(9.3, 35)
      ..quadraticBezierTo(14.2, 34.2, 17.4, 31)
      ..cubicTo(29, 33, 35.2, 26.9, 35.2, 18.8)
      ..cubicTo(35.2, 10, 29.6, 5, 20, 5)
      ..close();
    _surface(canvas, bubble, WanpanColors.surface);
    for (final x in [12.5, 20.1, 27.7]) {
      canvas.drawCircle(Offset(x, 19.5), 2, _fill(WanpanColors.coral));
    }
  }

  void _favorite(Canvas canvas) {
    final star = Path();
    for (var point = 0; point < 10; point++) {
      final angle = -math.pi / 2 + point * math.pi / 5;
      final radius = point.isEven ? 16.6 : 8.5;
      final x = 20 + math.cos(angle) * radius;
      final y = 20 + math.sin(angle) * radius;
      if (point == 0) {
        star.moveTo(x, y);
      } else {
        star.lineTo(x, y);
      }
    }
    star.close();
    _surface(canvas, star, WanpanColors.sunflower);
    canvas
      ..drawCircle(const Offset(17, 19), 1.45, _fill(WanpanColors.coral))
      ..drawCircle(const Offset(23, 19), 1.45, _fill(WanpanColors.coral));
  }

  void _like(Canvas canvas) {
    final heart = Path()
      ..moveTo(20, 34.5)
      ..cubicTo(15.1, 31.3, 3.7, 23.5, 3.7, 14.2)
      ..cubicTo(3.7, 4.3, 14.6, 3.1, 20, 10.4)
      ..cubicTo(25.4, 3.1, 36.3, 4.3, 36.3, 14.2)
      ..cubicTo(36.3, 23.5, 24.9, 31.3, 20, 34.5)
      ..close();
    _surface(canvas, heart, WanpanColors.coral);
    canvas.drawPath(
      Path()
        ..moveTo(9.5, 14)
        ..quadraticBezierTo(10.1, 10.4, 12.7, 10.5),
      Paint()
        ..color = WanpanColors.coralSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _route(Canvas canvas) {
    final route = Path()
      ..moveTo(10, 31)
      ..cubicTo(1, 20, 14, 3, 29, 8)
      ..cubicTo(43, 13, 32, 32, 17, 31);
    final metric = route.computeMetrics().first;
    final line = _outline..strokeWidth = 1.9;
    for (var start = 0.0; start < metric.length; start += 7.5) {
      canvas.drawPath(metric.extractPath(start, start + 3.5), line);
    }
    _hold(canvas, const Offset(29, 10), WanpanColors.coral, .85);
    _hold(canvas, const Offset(10, 31), WanpanColors.grape, .72);
  }

  void _hold(Canvas canvas, Offset center, Color color, double scale) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    final hold = Path()
      ..moveTo(-8, 1)
      ..cubicTo(-9, -5, -3, -10, 2, -7)
      ..cubicTo(6, -5, 10, -2, 9, 3)
      ..cubicTo(7, 8, -8, 9, -8, 1)
      ..close();
    _surface(canvas, hold, color);
    canvas
      ..drawCircle(Offset.zero, 2.4, _outline)
      ..drawCircle(Offset.zero, 1, _fill(WanpanColors.ink));
    canvas.restore();
  }

  void _friends(Canvas canvas) {
    void friend(double x, double y, Color color) {
      final person = Path()
        ..moveTo(x - 6, y + 3)
        ..cubicTo(x - 15, y - 9, x - 5, y - 20, x + 4, y - 16)
        ..cubicTo(x + 13, y - 13, x + 12, y - 3, x + 6, y + 3)
        ..quadraticBezierTo(x + 12, y + 7, x + 11, y + 12)
        ..quadraticBezierTo(x, y + 15, x - 11, y + 12)
        ..quadraticBezierTo(x - 12, y + 7, x - 6, y + 3)
        ..close();
      _surface(canvas, person, color);
      canvas
        ..drawCircle(Offset(x - 3.1, y - 8.4), 1.3, _fill(WanpanColors.ink))
        ..drawCircle(Offset(x + 3.1, y - 8.4), 1.3, _fill(WanpanColors.ink));
      canvas.drawPath(
        Path()
          ..moveTo(x - 2.4, y - 3.7)
          ..quadraticBezierTo(x, y - 1.2, x + 2.4, y - 3.7),
        _outline..strokeWidth = 1.45,
      );
    }

    friend(25, 22, WanpanColors.coral);
    friend(13, 23, WanpanColors.surface);
  }

  void _invite(Canvas canvas) {
    for (final (origin, color) in [
      (const Offset(3, 3), WanpanColors.coral),
      (const Offset(24, 3), WanpanColors.grape),
      (const Offset(3, 24), WanpanColors.grape),
    ]) {
      final square = RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, 13, 13),
        const Radius.circular(3.5),
      );
      canvas
        ..drawRRect(square, _fill(WanpanColors.surface))
        ..drawRRect(square, _outline)
        ..drawCircle(origin + const Offset(6.5, 6.5), 2.5, _fill(color));
    }
    final loop = _outline
      ..color = WanpanColors.grape
      ..strokeWidth = 2.7;
    canvas
      ..drawCircle(const Offset(27.3, 27.2), 3, loop)
      ..drawCircle(const Offset(27.3, 34.2), 3, loop)
      ..drawCircle(const Offset(35.2, 26.8), 2.5, _fill(WanpanColors.coral))
      ..drawCircle(const Offset(35.4, 34.9), 2, _fill(WanpanColors.grape));
  }

  @override
  bool shouldRepaint(_CartoonIconPainter oldDelegate) =>
      oldDelegate.kind != kind;
}
