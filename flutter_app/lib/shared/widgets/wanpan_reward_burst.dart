import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';

class WanpanRewardBurst extends StatefulWidget {
  const WanpanRewardBurst({
    required this.child,
    super.key,
    this.width = 250,
    this.height = 220,
    this.enableHaptics = false,
  });

  final Widget child;
  final double width;
  final double height;
  final bool enableHaptics;

  @override
  State<WanpanRewardBurst> createState() => _WanpanRewardBurstState();
}

class _WanpanRewardBurstState extends State<WanpanRewardBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WanpanMotion.celebration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (WanpanMotion.reduceMotion(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
    if (widget.enableHaptics) HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WanpanMotion.reduceMotion(context);
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) {
            final value = _controller.value;
            final pop = Curves.easeOutBack.transform(
              (value / .48).clamp(0.0, 1.0),
            );
            final settle = Curves.easeOut.transform(
              ((value - .48) / .52).clamp(0.0, 1.0),
            );
            final scale = reduceMotion ? 1.0 : .86 + .18 * pop - .04 * settle;
            final rise = reduceMotion ? 0.0 : 14 * (1 - pop);

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!reduceMotion)
                  for (final particle in _particles)
                    _RewardParticleView(particle: particle, value: value),
                Transform.translate(
                  offset: Offset(0, rise),
                  child: Transform.scale(scale: scale, child: child),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RewardParticle {
  const _RewardParticle({
    required this.offset,
    required this.color,
    required this.size,
    required this.rotation,
    this.star = false,
  });

  final Offset offset;
  final Color color;
  final double size;
  final double rotation;
  final bool star;
}

const _particles = [
  _RewardParticle(
    offset: Offset(-102, -66),
    color: WanpanColors.sunflower,
    size: 24,
    rotation: -.2,
    star: true,
  ),
  _RewardParticle(
    offset: Offset(100, -62),
    color: WanpanColors.sunflower,
    size: 20,
    rotation: .15,
    star: true,
  ),
  _RewardParticle(
    offset: Offset(-116, 20),
    color: WanpanColors.coral,
    size: 15,
    rotation: -.65,
  ),
  _RewardParticle(
    offset: Offset(113, 26),
    color: WanpanColors.grape,
    size: 14,
    rotation: .55,
  ),
  _RewardParticle(
    offset: Offset(-72, 84),
    color: WanpanColors.mint,
    size: 13,
    rotation: .35,
  ),
  _RewardParticle(
    offset: Offset(78, 86),
    color: WanpanColors.sky,
    size: 13,
    rotation: -.4,
  ),
];

class _RewardParticleView extends StatelessWidget {
  const _RewardParticleView({required this.particle, required this.value});

  final _RewardParticle particle;
  final double value;

  @override
  Widget build(BuildContext context) {
    final travel = Curves.easeOutCubic.transform((value / .72).clamp(0.0, 1.0));
    final appear = Curves.easeOut.transform((value / .22).clamp(0.0, 1.0));
    final fade =
        1 -
        .24 * Curves.easeIn.transform(((value - .72) / .28).clamp(0.0, 1.0));
    final size = particle.size;
    final shape = particle.star
        ? Icon(Icons.star_rounded, color: particle.color, size: size)
        : Container(
            width: size,
            height: size * .72,
            decoration: BoxDecoration(
              color: particle.color,
              borderRadius: BorderRadius.circular(size),
            ),
          );

    return Transform.translate(
      offset: particle.offset * travel,
      child: Transform.rotate(
        angle: particle.rotation * travel,
        child: Transform.scale(
          scale: .55 + .45 * appear,
          child: Opacity(opacity: appear * fade, child: shape),
        ),
      ),
    );
  }
}
