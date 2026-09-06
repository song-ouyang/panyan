import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/wanpan_theme.dart';
import '../motion/badge_feedback_preferences.dart';
import '../app_assets.dart';
import '../motion/wanpan_motion.dart';
import '../motion/wanpan_motion_sound.dart';
import 'wanpan_account_badge.dart';

class WanpanBadgeStage extends StatefulWidget {
  const WanpanBadgeStage({
    required this.level,
    this.size = 236,
    this.soundPlayer,
    super.key,
  });
  final int level;
  final double size;
  final WanpanMotionSoundPlayer? soundPlayer;
  @override
  State<WanpanBadgeStage> createState() => _WanpanBadgeStageState();
}

class _WanpanBadgeStageState extends State<WanpanBadgeStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final _player = widget.soundPlayer ?? WanpanAssetMotionSoundPlayer();
  final _preferences = BadgeFeedbackPreferences.instance;
  bool _started = false;
  bool _reduced = false;
  bool _active = true;
  Timer? _haptic;
  Timer? _preparationTimer;
  Completer<void>? _preparationReady;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preferences.addListener(_soundChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = WanpanMotion.reduceMotion(context);
    if (_reduced) _controller.value = 1;
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  Future<void> _start() async {
    await _prepareWithin(
      Future.wait<void>([
        precacheImage(const AssetImage(AppAssets.accountBadges), context),
        _preferences.load(),
      ]).then((_) {}),
      const Duration(milliseconds: 600),
    );
    if (!mounted || !_active) return;
    if (_preferences.enabled) {
      await _prepareWithin(
        _player.preload(const [WanpanMotionSoundCue.badgeEarned]),
        const Duration(milliseconds: 400),
      );
    }
    if (!mounted || !_active) return;
    if (!_reduced) _controller.forward(from: 0);
    if (_preferences.enabled) {
      unawaited(
        _player.play(WanpanMotionSoundCue.badgeEarned, animated: !_reduced),
      );
    }
    _haptic = Timer(
      _reduced ? Duration.zero : const Duration(milliseconds: 450),
      () async {
        try {
          await HapticFeedback.mediumImpact();
        } catch (_) {}
      },
    );
  }

  Future<void> _prepareWithin(Future<void> operation, Duration duration) async {
    final ready = Completer<void>();
    _preparationReady = ready;
    final timer = Timer(duration, () {
      if (!ready.isCompleted) ready.complete();
    });
    _preparationTimer = timer;
    unawaited(
      operation.then(
        (_) {
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object _) {
          if (!ready.isCompleted) ready.complete();
        },
      ),
    );
    await ready.future;
    timer.cancel();
    if (identical(_preparationReady, ready)) {
      _preparationReady = null;
      _preparationTimer = null;
    }
  }

  void _soundChanged() {
    if (!_preferences.enabled) unawaited(_player.stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _controller.value = 1;
      _haptic?.cancel();
      unawaited(_player.stop());
    }
  }

  @override
  void dispose() {
    _active = false;
    _preparationTimer?.cancel();
    final ready = _preparationReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    _haptic?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_soundChanged);
    _controller.dispose();
    unawaited(widget.soundPlayer == null ? _player.dispose() : _player.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      child: WanpanAccountBadge(level: widget.level, size: widget.size * .85),
      builder: (context, child) {
        final t = _controller.value;
        final scale = _reduced
            ? 1.0
            : t < .409
            ? .68 + .38 * Curves.easeOutCubic.transform(t / .409)
            : t < .818
            ? 1.06 - .06 * Curves.easeOut.transform((t - .409) / .409)
            : 1.0;
        final y = _reduced
            ? 0.0
            : t < .409
            ? 30 - 34 * Curves.easeOutCubic.transform(t / .409)
            : t < .818
            ? -4 + 4 * Curves.easeOut.transform((t - .409) / .409)
            : 0.0;
        final degrees = _reduced
            ? 0.0
            : t < .409
            ? -10 + 13 * Curves.easeOutCubic.transform(t / .409)
            : t < .818
            ? 3 - 3 * Curves.easeOut.transform((t - .409) / .409)
            : 0.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (!_reduced && t < .818)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _BadgeAccents(t)),
                ),
              ),
            Transform.translate(
              offset: Offset(0, y),
              child: Transform.rotate(
                angle: degrees * math.pi / 180,
                child: Transform.scale(scale: scale, child: child),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _BadgeAccents extends CustomPainter {
  const _BadgeAccents(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final opacity = (1 - progress / .818).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = WanpanColors.sunflower.withValues(alpha: opacity)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, size.width * (.28 + .21 * progress), paint);
    paint.style = PaintingStyle.fill;
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + .2;
      final radius = size.width * (.33 + .2 * progress);
      canvas.drawCircle(
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        2.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BadgeAccents oldDelegate) =>
      progress != oldDelegate.progress;
}
