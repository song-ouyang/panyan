import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import 'wanpan_pressable.dart';

class WanpanCard extends StatelessWidget {
  const WanpanCard({
    required this.child,
    super.key,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.color = WanpanColors.surface,
    this.borderColor = WanpanColors.border,
    this.radius = WanpanRadii.large,
    this.hasShadow = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final Color borderColor;
  final double radius;
  final bool hasShadow;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: hasShadow
            ? const [
                BoxShadow(
                  color: Color(0x0D75573A),
                  offset: Offset(0, 5),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}
