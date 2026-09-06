import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';

abstract final class WanpanLevelColors {
  static const palette = <Color>[
    Color(0xFFE9DCC7),
    Color(0xFF70B99A),
    Color(0xFF66BADD),
    Color(0xFFEF9277),
    Color(0xFFA68AD0),
    Color(0xFFF47757),
    Color(0xFFE8BD50),
    Color(0xFFD9AB42),
    Color(0xFFA985D5),
    Color(0xFFE8B45A),
    Color(0xFF695B47),
  ];
  static Color forLevel(int? level) => palette[(level ?? 0).clamp(0, 10)];
}

/// A level decorates the photo's outside edge; it never replaces the photo
/// with a medal. Lv.0 and unavailable growth keep an ordinary avatar border.
class WanpanLevelAvatar extends StatelessWidget {
  const WanpanLevelAvatar({
    required this.diameter,
    required this.level,
    this.image,
    this.placeholder,
    super.key,
  });
  final double diameter;
  final int? level;
  final ImageProvider<Object>? image;
  final Widget? placeholder;
  @override
  Widget build(BuildContext context) {
    final earned = (level ?? 0) > 0;
    final color = WanpanLevelColors.forLevel(level);
    final fallback =
        placeholder ??
        const Icon(Icons.person_rounded, color: WanpanColors.coral);
    return SizedBox.square(
      dimension: diameter,
      child: CustomPaint(
        foregroundPainter: earned ? _LevelRingPainter(color) : null,
        child: Padding(
          padding: EdgeInsets.all(earned ? 6 : 3),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WanpanColors.coralSoft,
              border: earned ? null : Border.all(color: WanpanColors.border),
            ),
            child: image == null
                ? Center(child: fallback)
                : Image(
                    image: ResizeImage.resizeIfNeeded(
                      (diameter * 3).ceil(),
                      (diameter * 3).ceil(),
                      image!,
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(child: fallback),
                  ),
          ),
        ),
      ),
    );
  }
}

class _LevelRingPainter extends CustomPainter {
  const _LevelRingPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    canvas.drawCircle(center, radius - .75, paint);
    paint
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .38);
    canvas.drawCircle(center, radius - 3, paint);
  }

  @override
  bool shouldRepaint(_LevelRingPainter oldDelegate) =>
      color != oldDelegate.color;
}
