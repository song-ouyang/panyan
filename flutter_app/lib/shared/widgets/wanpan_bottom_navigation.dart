import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';
import 'wanpan_pressable.dart';

enum WanpanTabIconKind { gym, feed, ranking, profile }

class WanpanBottomNavigation extends StatelessWidget {
  const WanpanBottomNavigation({
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _selectionDuration = Duration(milliseconds: 180);
  static const _radius = BorderRadius.all(Radius.circular(48));
  static const _items = [
    (kind: WanpanTabIconKind.gym, label: '岩馆'),
    (kind: WanpanTabIconKind.feed, label: '广场'),
    (kind: WanpanTabIconKind.ranking, label: '排行'),
    (kind: WanpanTabIconKind.profile, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    assert(currentIndex >= 0 && currentIndex < _items.length);
    final highContrast = MediaQuery.highContrastOf(context);
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        // Scrolling content must not invalidate the floating surface's paint.
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: _radius,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1824343C),
                  offset: Offset(0, 8),
                  blurRadius: 24,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              key: const ValueKey('wanpan-bottom-navigation-surface'),
              borderRadius: _radius,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // A dense translucent tint keeps text legible without a
                  // backdrop blur pass every time the page scrolls beneath it.
                  color: WanpanColors.surface.withValues(
                    alpha: highContrast ? 1 : .96,
                  ),
                  borderRadius: _radius,
                  border: Border.all(
                    color: highContrast
                        ? WanpanColors.muted
                        : Colors.white.withValues(alpha: .9),
                    width: 1.2,
                  ),
                ),
                child: SizedBox(
                  height: math.max(
                    74,
                    53 + MediaQuery.textScalerOf(context).scale(13) * 1.2,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FractionallySizedBox(
                              widthFactor: 1 / _items.length,
                              heightFactor: 1,
                              // Translation changes paint only; the four tab
                              // cells and labels keep their layout throughout.
                              child: AnimatedSlide(
                                offset: Offset(
                                  direction * currentIndex.toDouble(),
                                  0,
                                ),
                                duration: WanpanMotion.duration(
                                  context,
                                  _selectionDuration,
                                ),
                                curve: WanpanMotion.curve(context),
                                child: DecoratedBox(
                                  key: const ValueKey(
                                    'wanpan-bottom-navigation-selection',
                                  ),
                                  decoration: BoxDecoration(
                                    color: WanpanColors.coral.withValues(
                                      alpha: highContrast ? .18 : .11,
                                    ),
                                    borderRadius: _radius,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var index = 0; index < _items.length; index++)
                              Expanded(
                                child: _WanpanBottomTab(
                                  key: ValueKey('wanpan-bottom-tab-$index'),
                                  kind: _items[index].kind,
                                  label: _items[index].label,
                                  selected: currentIndex == index,
                                  onTap: () => onSelected(index),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WanpanBottomTab extends StatelessWidget {
  const _WanpanBottomTab({
    required this.kind,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final WanpanTabIconKind kind;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? WanpanColors.coral : WanpanColors.ink;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: WanpanPressable(
            onTap: onTap,
            pressedScale: .965,
            pressedOffset: 1,
            borderRadius: BorderRadius.circular(WanpanRadii.large),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 38,
                  child: Center(
                    child: WanpanTabIcon(kind: kind, color: foreground),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WanpanTabIcon extends StatelessWidget {
  const WanpanTabIcon({required this.kind, required this.color, super.key});

  final WanpanTabIconKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size.square(34),
      painter: _WanpanTabIconPainter(kind: kind, color: color),
    ),
  );
}

class _WanpanTabIconPainter extends CustomPainter {
  const _WanpanTabIconPainter({required this.kind, required this.color});

  final WanpanTabIconKind kind;
  final Color color;

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 32;
    canvas
      ..save()
      ..translate((size.width - 32 * scale) / 2, (size.height - 32 * scale) / 2)
      ..scale(scale);

    switch (kind) {
      case WanpanTabIconKind.gym:
        _paintGym(canvas);
      case WanpanTabIconKind.feed:
        _paintFeed(canvas);
      case WanpanTabIconKind.ranking:
        _paintRanking(canvas);
      case WanpanTabIconKind.profile:
        _paintProfile(canvas);
    }
    canvas.restore();
  }

  void _paintGym(Canvas canvas) {
    final house = Path()
      ..moveTo(5.5, 13)
      ..quadraticBezierTo(5.7, 11.5, 7, 10.4)
      ..lineTo(13.7, 5.1)
      ..quadraticBezierTo(16, 3.4, 18.3, 5.1)
      ..lineTo(25, 10.4)
      ..quadraticBezierTo(26.3, 11.5, 26.5, 13)
      ..lineTo(27.4, 24.1)
      ..quadraticBezierTo(27.6, 27, 24.7, 27.5)
      ..quadraticBezierTo(16, 29.1, 7.3, 27.5)
      ..quadraticBezierTo(4.4, 27, 4.6, 24.1)
      ..close();
    canvas.drawPath(house, _stroke);
    _hold(canvas, const Offset(12, 15), WanpanColors.coral, 2.15);
    _hold(canvas, const Offset(20.2, 17.2), WanpanColors.grape, 2.05);
    _hold(canvas, const Offset(14.7, 23.1), WanpanColors.sunflower, 1.85);
  }

  void _paintFeed(Canvas canvas) {
    final rear = Path()
      ..moveTo(15, 11.5)
      ..cubicTo(12.9, 11.5, 11.4, 13.1, 11.4, 15.2)
      ..lineTo(11.4, 19.8)
      ..cubicTo(11.4, 22.2, 13.2, 23.7, 15.5, 23.7)
      ..lineTo(20.3, 23.7)
      ..lineTo(24.8, 27)
      ..lineTo(24, 23.1)
      ..cubicTo(26.4, 22.4, 27.7, 20.8, 27.7, 18.6)
      ..lineTo(27.7, 16.8)
      ..cubicTo(27.7, 13.8, 25.4, 11.5, 22.4, 11.5)
      ..close();
    canvas.drawPath(rear, _stroke);

    final front = Path()
      ..moveTo(9.2, 6.1)
      ..lineTo(16.8, 6.1)
      ..cubicTo(19.9, 6.1, 22.1, 8.4, 22.1, 11.3)
      ..lineTo(22.1, 14.1)
      ..cubicTo(22.1, 17.2, 19.8, 19.4, 16.8, 19.4)
      ..lineTo(12, 19.4)
      ..lineTo(7.2, 22.6)
      ..lineTo(8.1, 18.8)
      ..cubicTo(5.5, 18.3, 3.9, 16.5, 3.9, 14)
      ..lineTo(3.9, 11.3)
      ..cubicTo(3.9, 8.4, 6.2, 6.1, 9.2, 6.1)
      ..close();
    canvas
      ..drawPath(front, Paint()..color = WanpanColors.surface)
      ..drawPath(front, _stroke)
      ..drawCircle(
        const Offset(11.1, 12.9),
        1.85,
        Paint()..color = WanpanColors.coral,
      )
      ..drawCircle(const Offset(17.2, 12.9), 1.85, Paint()..color = color);
  }

  void _paintRanking(Canvas canvas) {
    final trophy = Path()
      ..moveTo(9.2, 6.1)
      ..lineTo(22.8, 6.1)
      ..lineTo(21.7, 13.5)
      ..cubicTo(21.2, 17, 19.1, 19.2, 16, 19.2)
      ..cubicTo(12.9, 19.2, 10.8, 17, 10.3, 13.5)
      ..close();
    canvas.drawPath(trophy, _stroke);

    final leftHandle = Path()
      ..moveTo(9.5, 8.1)
      ..lineTo(6.5, 8.1)
      ..cubicTo(4.3, 8.1, 3.4, 9.5, 3.8, 11.8)
      ..cubicTo(4.4, 15.1, 6.5, 16.6, 10.7, 16.6);
    final rightHandle = Path()
      ..moveTo(22.5, 8.1)
      ..lineTo(25.5, 8.1)
      ..cubicTo(27.7, 8.1, 28.6, 9.5, 28.2, 11.8)
      ..cubicTo(27.6, 15.1, 25.5, 16.6, 21.3, 16.6);
    canvas
      ..drawPath(leftHandle, _stroke)
      ..drawPath(rightHandle, _stroke)
      ..drawLine(const Offset(16, 19.3), const Offset(16, 27), _stroke)
      ..drawLine(const Offset(10.4, 27), const Offset(21.6, 27), _stroke);

    canvas.drawPath(
      _starPath(const Offset(16, 12.1), 4.1, 1.9),
      Paint()
        ..color = WanpanColors.sunflower
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  void _paintProfile(Canvas canvas) {
    final head = Path()
      ..moveTo(6, 15)
      ..lineTo(6.1, 5.2)
      ..lineTo(12.1, 10.1)
      ..cubicTo(14.4, 9.1, 17.6, 9.1, 19.9, 10.1)
      ..lineTo(25.9, 5.2)
      ..lineTo(26, 15)
      ..cubicTo(26, 22.8, 22.3, 27.1, 16, 27.1)
      ..cubicTo(9.7, 27.1, 6, 22.8, 6, 15)
      ..close();
    canvas.drawPath(head, _stroke);
    canvas
      ..drawCircle(const Offset(12.2, 17.1), 2.5, _stroke)
      ..drawCircle(const Offset(19.8, 17.1), 2.5, _stroke);
    final pupil = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas
      ..drawCircle(const Offset(12.2, 17.2), .75, pupil)
      ..drawCircle(const Offset(19.8, 17.2), .75, pupil);
  }

  void _hold(Canvas canvas, Offset center, Color fill, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  Path _starPath(Offset center, double outerRadius, double innerRadius) {
    final path = Path();
    for (var point = 0; point < 10; point++) {
      final angle = -math.pi / 2 + point * math.pi / 5;
      final radius = point.isEven ? outerRadius : innerRadius;
      final offset = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (point == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_WanpanTabIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
