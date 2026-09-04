import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';

class WanpanPressable extends StatefulWidget {
  const WanpanPressable({
    required this.child,
    required this.onTap,
    super.key,
    this.semanticLabel,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.pressedScale = .97,
    this.pressedOffset = 1.5,
    this.enableHaptics = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final BorderRadius borderRadius;
  final double pressedScale;
  final double pressedOffset;
  final bool enableHaptics;

  @override
  State<WanpanPressable> createState() => _WanpanPressableState();
}

class _WanpanPressableState extends State<WanpanPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: WanpanMotion.touchDown,
    reverseDuration: WanpanMotion.tactileRelease,
  );
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || widget.onTap == null) return;
    setState(() => _pressed = value);
    if (value) {
      _pressController.animateTo(
        1,
        duration: WanpanMotion.touchDown,
        curve: WanpanMotion.easeOut,
      );
    } else {
      _pressController.animateBack(
        0,
        duration: WanpanMotion.tactileRelease,
        curve: WanpanMotion.playfulRelease,
      );
    }
  }

  void _tap() {
    if (widget.enableHaptics) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  void didUpdateWidget(covariant WanpanPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null && _pressed) {
      _pressed = false;
      _pressController.value = 0;
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduceMotion = WanpanMotion.reduceMotion(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: enabled ? _tap : null,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : .46,
            duration: WanpanMotion.duration(context, WanpanMotion.press),
            curve: WanpanMotion.curve(context),
            child: AnimatedBuilder(
              animation: _pressController,
              child: widget.child,
              builder: (context, child) {
                final progress = reduceMotion ? 0.0 : _pressController.value;
                return Transform.translate(
                  offset: Offset(0, widget.pressedOffset * progress),
                  child: Transform.scale(
                    scale: 1 - (1 - widget.pressedScale) * progress,
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum WanpanButtonStyle { primary, secondary, quiet, danger }

class WanpanButton extends StatefulWidget {
  const WanpanButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.style = WanpanButtonStyle.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final WanpanButtonStyle style;
  final Widget? icon;
  final bool loading;
  final bool expand;
  final String? semanticLabel;

  @override
  State<WanpanButton> createState() => _WanpanButtonState();
}

class _WanpanButtonState extends State<WanpanButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _activate() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
    widget.onPressed?.call();
  }

  void _setPressed(bool value) {
    if (!_enabled || value == _pressed) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _ButtonPalette.forStyle(widget.style);
    final physical = widget.style == WanpanButtonStyle.primary;
    final reduceMotion = WanpanMotion.reduceMotion(context);
    final depth = physical ? 6.0 : 0.0;
    final travel = physical && _pressed && !reduceMotion ? 4.0 : 0.0;
    final motionDuration = _pressed
        ? WanpanMotion.touchDown
        : WanpanMotion.tactileRelease;
    final motionCurve = _pressed
        ? WanpanMotion.easeOut
        : WanpanMotion.playfulRelease;

    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: palette.foreground),
    );

    final content = AnimatedContainer(
      duration: WanpanMotion.duration(context, motionDuration),
      curve: WanpanMotion.curve(context, motionCurve),
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
        boxShadow: physical
            ? [
                BoxShadow(
                  color: palette.depth,
                  offset: Offset(0, _pressed ? 1 : depth),
                  blurRadius: 0,
                ),
              ]
            : const [],
      ),
      transform: Matrix4.translationValues(0, travel, 0),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.loading)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: palette.foreground,
              ),
            )
          else if (widget.icon != null)
            IconTheme(
              data: IconThemeData(color: palette.foreground, size: 20),
              child: widget.icon!,
            ),
          if (widget.loading || widget.icon != null) const SizedBox(width: 10),
          if (widget.expand) Flexible(child: label) else label,
        ],
      ),
    );

    final tactileContent = AnimatedScale(
      scale: reduceMotion || !_pressed ? 1 : .985,
      duration: WanpanMotion.duration(context, motionDuration),
      curve: WanpanMotion.curve(context, motionCurve),
      child: content,
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      liveRegion: widget.loading,
      label: widget.loading
          ? '${widget.semanticLabel ?? widget.label}，正在处理'
          : widget.semanticLabel ?? widget.label,
      onTap: _enabled ? _activate : null,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => _setPressed(true) : null,
            onTapUp: _enabled ? (_) => _setPressed(false) : null,
            onTapCancel: _enabled ? () => _setPressed(false) : null,
            onTap: _enabled ? _activate : null,
            child: AnimatedOpacity(
              opacity: _enabled ? 1 : .46,
              duration: WanpanMotion.duration(context, WanpanMotion.press),
              child: Padding(
                padding: EdgeInsets.only(bottom: depth),
                child: widget.expand
                    ? SizedBox(width: double.infinity, child: tactileContent)
                    : tactileContent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonPalette {
  const _ButtonPalette({
    required this.background,
    required this.foreground,
    required this.border,
    required this.depth,
  });

  factory _ButtonPalette.forStyle(WanpanButtonStyle style) => switch (style) {
    WanpanButtonStyle.primary => const _ButtonPalette(
      background: WanpanColors.coral,
      foreground: WanpanColors.ink,
      border: WanpanColors.coral,
      depth: WanpanColors.coralStrong,
    ),
    WanpanButtonStyle.secondary => const _ButtonPalette(
      background: WanpanColors.surfaceSoft,
      foreground: WanpanColors.ink,
      border: WanpanColors.border,
      depth: Colors.transparent,
    ),
    WanpanButtonStyle.quiet => const _ButtonPalette(
      background: WanpanColors.surface,
      foreground: WanpanColors.coralStrong,
      border: WanpanColors.border,
      depth: Colors.transparent,
    ),
    WanpanButtonStyle.danger => const _ButtonPalette(
      background: Color(0xFFFFF1EF),
      foreground: WanpanColors.danger,
      border: Color(0x33C94C3F),
      depth: Colors.transparent,
    ),
  };

  final Color background;
  final Color foreground;
  final Color border;
  final Color depth;
}
