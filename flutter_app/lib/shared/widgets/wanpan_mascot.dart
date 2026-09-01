import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../app_assets.dart';

class WanpanMascot extends StatelessWidget {
  const WanpanMascot({
    super.key,
    this.asset = AppAssets.mascotWelcome,
    this.width = 144,
    this.height = 144,
    this.radius = 28,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String asset;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        asset,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => ColoredBox(
          color: WanpanColors.coralSoft,
          child: SizedBox(
            width: width,
            height: height,
            child: const Icon(
              Icons.pets_rounded,
              size: 48,
              color: WanpanColors.coral,
            ),
          ),
        ),
      ),
    ),
  );
}

class WanpanSectionTitle extends StatelessWidget {
  const WanpanSectionTitle({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}
