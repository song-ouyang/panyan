import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';

/// A compact calendar bar whose color keeps the same meaning on every date.
class WanpanCalendarBadge extends StatelessWidget {
  WanpanCalendarBadge.count({required int count, this.textKey, super.key})
    : label = '$count条',
      backgroundColor = switch (count) {
        <= 1 => const Color(0xFFE2F3E7),
        <= 3 => const Color(0xFFBDE5CD),
        <= 6 => const Color(0xFFFFE6A0),
        <= 9 => const Color(0xFFFFCB9D),
        _ => const Color(0xFFFFAB9F),
      };

  WanpanCalendarBadge.grade({required int grade, this.textKey, super.key})
    : label = 'V$grade',
      backgroundColor = _gradeColors[grade.clamp(0, 17)];

  static const _gradeColors = [
    Color(0xFFDDF0F5), // V0 · sky
    Color(0xFFC2E8DE), // V1 · mint
    Color(0xFFFFEBAC), // V2 · sunflower
    Color(0xFFFFB7A5), // V3 · coral
    Color(0xFFDABFEA), // V4 · grape
    Color(0xFFBADFEF), // V5
    Color(0xFFD8E9AC), // V6
    Color(0xFFFFD891), // V7
    Color(0xFFFFCAA4), // V8 · peach
    Color(0xFFF5ABBA), // V9 · rose
    Color(0xFFECC0D8), // V10
    Color(0xFFC3B9EC), // V11
    Color(0xFFB7CBEC), // V12 · periwinkle
    Color(0xFFA4D6DD), // V13
    Color(0xFFAFD8BE), // V14 · sage
    Color(0xFFD4CEAA), // V15
    Color(0xFFE4C1A5), // V16 · clay
    Color(0xFFCCA9B4), // V17
  ];

  final String label;
  final Color backgroundColor;
  final Key? textKey;

  static double heightOf(BuildContext context) =>
      6 + MediaQuery.textScalerOf(context).scale(12);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: heightOf(context),
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(5),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        key: textKey,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: WanpanColors.ink,
        ),
      ),
    ),
  );
}
