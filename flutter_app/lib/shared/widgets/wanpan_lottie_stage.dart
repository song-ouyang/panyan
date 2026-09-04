import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';

typedef WanpanLottiePresented = void Function(bool animated);
typedef WanpanLottieCompleted = void Function(bool animated);

/// Warms a Lottie composition without blocking the current screen.
///
/// Loading failures are intentionally swallowed because every runtime stage
/// has a static mascot fallback. Preloading is only a latency optimisation and
/// must never change a product flow into an error state.
Future<void> preloadWanpanLottie(BuildContext context, String asset) async {
  try {
    await AssetLottie(asset, backgroundLoading: true).load(context: context);
  } catch (_) {
    // The stage will present its accessible fallback if the asset is missing.
  }
}

/// A non-interactive, one-shot Lottie stage for meaningful product feedback.
///
/// The animation plays once for each [asset] assigned to this widget and stays
/// on its final frame. When reduced motion is enabled, it skips directly to
/// that final frame instead.
class WanpanLottieStage extends StatefulWidget {
  const WanpanLottieStage({
    required this.asset,
    required this.semanticLabel,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.play = true,
    this.onPresented,
    this.onCompleted,
    this.fallback = const Icon(
      Icons.pets_rounded,
      size: 64,
      color: WanpanColors.coral,
    ),
  });

  final String asset;
  final String semanticLabel;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final bool play;

  /// Called once per [asset] when feedback first becomes visible.
  ///
  /// [animated] is false for reduced motion, a deliberately skipped replay,
  /// or a static fallback. Feature screens can use this to keep a causal
  /// haptic while avoiding animation-timed delays in those modes.
  final WanpanLottiePresented? onPresented;

  /// Called once per [asset] after playback reaches its stable final frame.
  ///
  /// [animated] is false when reduced motion, a skipped replay, or a fallback
  /// resolves directly to the final state.
  final WanpanLottieCompleted? onCompleted;
  final Widget fallback;

  @override
  State<WanpanLottieStage> createState() => _WanpanLottieStageState();
}

class _WanpanLottieStageState extends State<WanpanLottieStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _reduceMotion = false;
  bool _hasLoaded = false;
  bool _hasPlayed = false;
  bool _hasPresented = false;
  bool _presentationScheduled = false;
  bool _hasCompleted = false;
  bool _completionScheduled = false;
  String? _loadedAsset;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasReduced = _reduceMotion;
    _reduceMotion = WanpanMotion.reduceMotion(context);
    if (_reduceMotion && _hasLoaded) {
      _controller.stop();
      _controller.value = 1;
      _present(animated: false);
      _complete(animated: false);
    } else if (wasReduced && !_reduceMotion && !_hasPresented) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant WanpanLottieStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _controller.reset();
      _hasLoaded = false;
      _hasPlayed = false;
      _hasPresented = false;
      _presentationScheduled = false;
      _hasCompleted = false;
      _completionScheduled = false;
      _loadedAsset = null;
      return;
    }
    if (oldWidget.play == widget.play || !_hasLoaded) return;
    if (!widget.play) {
      _controller.stop();
      _controller.value = 1;
      _present(animated: false);
      _complete(animated: false);
    } else {
      _startAnimation();
    }
  }

  void _handleLoaded(String asset, LottieComposition composition) {
    if (asset != widget.asset || _loadedAsset == asset) return;
    _loadedAsset = asset;
    _hasLoaded = true;
    _controller.duration = composition.duration;
    if (_reduceMotion || !widget.play) {
      _controller.value = 1;
      _present(animated: false);
      _complete(animated: false);
      return;
    }
    _startAnimation();
  }

  void _startAnimation() {
    if (!_hasLoaded || _hasPlayed || _reduceMotion || !widget.play) return;
    _hasPlayed = true;
    final asset = widget.asset;
    _controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || widget.asset != asset) return;
      if (_controller.status != AnimationStatus.completed) return;
      _complete(animated: true);
    });
    _present(animated: true);
  }

  void _present({required bool animated}) {
    if (_hasPresented || _presentationScheduled) return;
    _presentationScheduled = true;
    final asset = widget.asset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.asset != asset) return;
      _presentationScheduled = false;
      if (_hasPresented) return;
      _hasPresented = true;
      widget.onPresented?.call(animated);
    });
  }

  void _complete({required bool animated}) {
    if (_hasCompleted || _completionScheduled) return;
    _completionScheduled = true;
    final asset = widget.asset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.asset != asset) return;
      _completionScheduled = false;
      if (_hasCompleted) return;
      _hasCompleted = true;
      widget.onCompleted?.call(animated);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Lottie.asset(
                asset,
                controller: _controller,
                repeat: false,
                fit: widget.fit,
                alignment: widget.alignment,
                frameRate: FrameRate.composition,
                backgroundLoading: true,
                addRepaintBoundary: false,
                onLoaded: (composition) => _handleLoaded(asset, composition),
                frameBuilder: (_, child, composition) =>
                    composition == null ? widget.fallback : child,
                errorBuilder: (_, _, _) {
                  _present(animated: false);
                  _complete(animated: false);
                  return widget.fallback;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
