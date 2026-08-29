import 'package:flutter/material.dart';

abstract final class WanpanMotion {
  static const instant = Duration.zero;
  static const press = Duration(milliseconds: 130);
  static const exit = Duration(milliseconds: 160);
  static const enter = Duration(milliseconds: 220);
  static const progress = Duration(milliseconds: 260);
  static const easeOut = Cubic(.23, 1, .32, 1);
  static const easeInOut = Cubic(.77, 0, .175, 1);
  static const sheet = Cubic(.32, .72, 0, 1);

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration duration(
    BuildContext context,
    Duration preferred, {
    Duration reduced = const Duration(milliseconds: 1),
  }) => reduceMotion(context) ? reduced : preferred;

  static Curve curve(BuildContext context, [Curve preferred = easeOut]) =>
      reduceMotion(context) ? Curves.linear : preferred;
}
