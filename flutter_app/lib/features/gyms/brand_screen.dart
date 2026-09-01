import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/gym_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';

class BrandScreen extends StatefulWidget {
  const BrandScreen({required this.api, required this.brandId, super.key});

  final ApiClient api;
  final String brandId;

  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  late final GymRepository _repository = GymRepository(widget.api);
  GymBrandDetail? _detail;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await _repository.getBrandStores(widget.brandId);
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_detail?.name ?? '门店')),
    body: _body(),
  );

  Widget _body() {
    final detail = _detail;
    if (detail == null && _error == null) {
      return const WanpanListSkeleton(itemCount: 4);
    }
    if (detail == null) {
      return WanpanErrorState(title: '门店没有加载出来', onRetry: _load);
    }
    if (detail.stores.isEmpty) {
      return const WanpanEmptyState(
        title: '这个品牌还没有门店',
        description: '岩馆入驻后会显示在这里。',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: WanpanColors.coral,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          WanpanCard(
            color: WanpanColors.skySoft,
            borderColor: WanpanColors.sky,
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            child: _BrandSummary(detail: detail),
          ),
          const SizedBox(height: 24),
          Text('选择门店', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...detail.stores.map(
            (gym) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WanpanCard(
                semanticLabel: '打开${gym.name}',
                onTap: () => context.push('/gyms/${gym.id}'),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: WanpanColors.goldSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: WanpanColors.gold,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gym.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${gym.district ?? gym.city} · ${gym.routeCount} 条线路',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: WanpanColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandSummary extends StatelessWidget {
  const _BrandSummary({required this.detail});

  final GymBrandDetail detail;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'brand-${detail.id}',
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: WanpanColors.coralSoft,
                  borderRadius: BorderRadius.circular(21),
                ),
                clipBehavior: Clip.antiAlias,
                child: detail.logoUrl == null
                    ? const Icon(
                        Icons.landscape_rounded,
                        color: WanpanColors.coral,
                        size: 32,
                      )
                    : Image.network(
                        detail.logoUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 220,
                        cacheHeight: 220,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.landscape_rounded,
                          color: WanpanColors.coral,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              detail.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 5),
            Text(
              '${detail.stores.length} 家门店 · 一起去发现新线路',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      const WanpanMascot(
        asset: AppAssets.mascotLoading,
        width: 116,
        height: 142,
        radius: 26,
      ),
    ],
  );
}
