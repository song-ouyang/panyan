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
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(WanpanRadii.large),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F17191C),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(WanpanRadii.large),
      child: card,
    );
  }
}
