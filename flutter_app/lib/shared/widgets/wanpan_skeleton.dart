import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';

class WanpanSkeleton extends StatefulWidget {
  const WanpanSkeleton({
    super.key,
    this.width,
    this.height = 18,
    this.borderRadius = 12,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<WanpanSkeleton> createState() => _WanpanSkeletonState();
}

class _WanpanSkeletonState extends State<WanpanSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WanpanMotion.reduceMotion(context)) {
      _controller.stop();
      _controller.value = .72;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, _) => Opacity(
      opacity: .52 + (_controller.value * .36),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: WanpanColors.surfaceMuted,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    ),
  );
}

class WanpanListSkeleton extends StatelessWidget {
  const WanpanListSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(WanpanSpacing.page),
    itemCount: itemCount,
    separatorBuilder: (_, _) => const SizedBox(height: 14),
    itemBuilder: (_, _) => Container(
      height: 104,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WanpanColors.surface,
        border: Border.all(color: WanpanColors.border),
        borderRadius: BorderRadius.circular(WanpanRadii.large),
      ),
      child: const Row(
        children: [
          WanpanSkeleton(width: 64, height: 64, borderRadius: 18),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WanpanSkeleton(width: 136, height: 20),
                SizedBox(height: 12),
                WanpanSkeleton(width: 88, height: 14),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
