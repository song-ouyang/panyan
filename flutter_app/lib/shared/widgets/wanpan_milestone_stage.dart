import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../app_assets.dart';
import '../motion/wanpan_motion.dart';
import 'wanpan_lottie_stage.dart';

/// The milestone Lottie plus accessible, data-driven V-grade labels.
///
/// Grade text intentionally lives in Flutter rather than the animation JSON,
/// so production screens can pass real user data and the motion lab can use a
/// deterministic demo/configured sequence.
class WanpanMilestoneStage extends StatefulWidget {
  const WanpanMilestoneStage({
    required this.grades,
    required this.semanticLabel,
    required this.width,
    required this.height,
    super.key,
    this.asset = AppAssets.gradeMilestoneAnimation,
    this.play = true,
    this.onPresented,
    this.fallback = const Icon(
      Icons.pets_rounded,
      size: 64,
      color: WanpanColors.coral,
    ),
  }) : assert(grades.length == 3);

  final List<String> grades;
  final String semanticLabel;
  final double width;
  final double height;
  final String asset;
  final bool play;
  final WanpanLottiePresented? onPresented;
  final Widget fallback;

  @override
  State<WanpanMilestoneStage> createState() => _WanpanMilestoneStageState();
}

class _WanpanMilestoneStageState extends State<WanpanMilestoneStage> {
  bool _gradesVisible = false;
  bool _animateGrades = false;

  void _handlePresented(bool animated) {
    if (mounted && !_gradesVisible) {
      setState(() {
        _gradesVisible = true;
        _animateGrades = animated;
      });
    }
    widget.onPresented?.call(animated);
  }

  @override
  Widget build(BuildContext context) {
    final gradeDescription = widget.grades.join('到');
    return Semantics(
      image: true,
      label: '${widget.semanticLabel}，难度进阶$gradeDescription',
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WanpanLottieStage(
                asset: widget.asset,
                semanticLabel: widget.semanticLabel,
                width: widget.width,
                height: widget.height,
                play: widget.play,
                onPresented: _handlePresented,
                fallback: widget.fallback,
              ),
              WanpanMilestoneGradeOverlay(
                grades: widget.grades,
                visible: _gradesVisible,
                animated: _animateGrades,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Positions three grade labels over the safe areas in the canonical
/// `grade-milestone.json` 512×512 composition.
class WanpanMilestoneGradeOverlay extends StatefulWidget {
  const WanpanMilestoneGradeOverlay({
    required this.grades,
    super.key,
    this.visible = true,
    this.animated = true,
  }) : assert(grades.length == 3);

  final List<String> grades;
  final bool visible;
  final bool animated;

  @override
  State<WanpanMilestoneGradeOverlay> createState() =>
      _WanpanMilestoneGradeOverlayState();
}

class _WanpanMilestoneGradeOverlayState
    extends State<WanpanMilestoneGradeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WanpanMotion.celebration,
  );
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible && !widget.animated) _controller.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = WanpanMotion.reduceMotion(context);
    _syncPresentation(restart: false);
  }

  @override
  void didUpdateWidget(covariant WanpanMilestoneGradeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final gradesChanged = !listEquals(oldWidget.grades, widget.grades);
    _syncPresentation(
      restart: gradesChanged || (!oldWidget.visible && widget.visible),
    );
  }

  void _syncPresentation({required bool restart}) {
    if (!widget.visible) {
      _controller.value = 0;
      return;
    }
    if (_reduceMotion || !widget.animated) {
      _controller.value = 1;
      return;
    }
    if (restart || _controller.value == 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '难度进阶 ${widget.grades.join(' 到 ')}',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const positions = <Offset>[
                Offset(.266, .613),
                Offset(.5, .559),
                Offset(.734, .613),
              ];
              final compositionSize = constraints.biggest.shortestSide;
              final compositionOrigin = Offset(
                (constraints.maxWidth - compositionSize) / 2,
                (constraints.maxHeight - compositionSize) / 2,
              );
              final labelSize = (compositionSize * .12).clamp(28.0, 52.0);
              return Stack(
                children: [
                  for (var index = 0; index < widget.grades.length; index += 1)
                    _positionedGrade(
                      context: context,
                      position: positions[index],
                      compositionSize: compositionSize,
                      compositionOrigin: compositionOrigin,
                      labelSize: labelSize,
                      index: index,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _positionedGrade({
    required BuildContext context,
    required Offset position,
    required double compositionSize,
    required Offset compositionOrigin,
    required double labelSize,
    required int index,
  }) {
    final intervalStart = .25 + index * .18;
    final intervalEnd = (intervalStart + .2).clamp(0.0, 1.0);
    final opacity = CurvedAnimation(
      parent: _controller,
      curve: Interval(intervalStart, intervalEnd, curve: WanpanMotion.easeOut),
    );
    final scale = Tween<double>(begin: .88, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          intervalStart,
          intervalEnd,
          curve: WanpanMotion.playfulRelease,
        ),
      ),
    );
    return Positioned(
      left:
          compositionOrigin.dx + compositionSize * position.dx - labelSize / 2,
      top: compositionOrigin.dy + compositionSize * position.dy - labelSize / 2,
      width: labelSize,
      height: labelSize,
      child: FadeTransition(
        opacity: opacity,
        child: ScaleTransition(
          scale: scale,
          child: Center(
            child: Text(
              widget.grades[index],
              key: ValueKey('milestone-grade-$index'),
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: WanpanColors.ink,
                fontSize: labelSize * .48,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
