import 'package:flutter/material.dart';

abstract final class WanpanMotion {
  static const instant = Duration.zero;
  static const touchDown = Duration(milliseconds: 90);
  static const press = Duration(milliseconds: 110);
  static const exit = Duration(milliseconds: 160);
  static const enter = Duration(milliseconds: 220);
  static const selection = Duration(milliseconds: 280);
  static const tactileRelease = Duration(milliseconds: 320);
  static const progress = Duration(milliseconds: 320);
  static const celebration = Duration(milliseconds: 820);
  static const easeOut = Cubic(.23, 1, .32, 1);
  static const easeInOut = Cubic(.77, 0, .175, 1);
  static const sheet = Cubic(.32, .72, 0, 1);
  static const playfulRelease = Cubic(.2, 1.24, .32, 1);

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
