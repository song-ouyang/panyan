import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../app_assets.dart';
import 'wanpan_pressable.dart';

class WanpanEmptyState extends StatelessWidget {
  const WanpanEmptyState({
    required this.title,
    super.key,
    this.description,
    this.actionLabel,
    this.onAction,
    this.imageAsset = AppAssets.mascotWelcome,
  });

  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? imageAsset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageAsset != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              imageAsset!,
              width: 152,
              height: 132,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.landscape_rounded,
                size: 72,
                color: WanpanColors.coral,
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          WanpanButton(label: actionLabel!, onPressed: onAction, expand: false),
        ],
      ],
    ),
  );
}

class WanpanErrorState extends StatelessWidget {
  const WanpanErrorState({
    required this.title,
    required this.onRetry,
    super.key,
    this.description = '网络恢复后，点击下面按钮重新加载。',
  });

  final String title;
  final String description;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => WanpanEmptyState(
    title: title,
    description: description,
    actionLabel: '重新加载',
    onAction: onRetry,
    imageAsset: null,
  );
}
