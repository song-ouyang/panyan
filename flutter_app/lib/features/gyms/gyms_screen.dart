import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/gym_repository.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';

class GymsScreen extends StatefulWidget {
  const GymsScreen({required this.api, super.key});

  final ApiClient api;

  @override
  State<GymsScreen> createState() => _GymsScreenState();
}

class _GymsScreenState extends State<GymsScreen> {
  late final GymRepository _repository = GymRepository(widget.api);
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<GymDirectoryItem> _items = const [];
  String? _city;
  Object? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.getDirectory(
        city: _city,
        query: _searchController.text.trim(),
      );
      if (!mounted || requestId != _requestId) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error);
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _search(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), _load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('岩馆'),
      actions: [
        TextButton.icon(
          onPressed: () => context.push('/routes/pick'),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('找线路'),
        ),
        IconButton(
          tooltip: '直接发布新线路',
          onPressed: () => context.push('/route-submissions/new'),
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WanpanSpacing.page,
            WanpanSpacing.sm,
            WanpanSpacing.page,
            WanpanSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _search,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索岩馆或品牌',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _CityButton(
                value: _city,
                cities: _availableCities,
                onChanged: (city) {
                  if (city == _city) return;
                  setState(() => _city = city);
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Set<String> get _availableCities => _items.map((item) => item.city).toSet();

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const WanpanListSkeleton(itemCount: 5);
    }
    if (_error != null && _items.isEmpty) {
      return WanpanErrorState(title: '岩馆列表没有加载出来', onRetry: _load);
    }
    if (_items.isEmpty) {
      return WanpanEmptyState(
        title: '还没有找到岩馆',
        description: '换一个城市或关键词试试。',
        actionLabel: '清空筛选',
        onAction: () {
          _searchController.clear();
          setState(() => _city = null);
          _load();
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: WanpanColors.coral,
      child: ListView.separated(
        key: const PageStorageKey('gym-directory'),
        padding: const EdgeInsets.fromLTRB(
          WanpanSpacing.page,
          0,
          WanpanSpacing.page,
          104,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          return WanpanCard(
            semanticLabel: '打开${item.brandName}',
            onTap: () => context.push('/brands/${item.brandId}'),
            child: Row(
              children: [
                _BrandMark(item: item),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.brandName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (item.verified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              color: WanpanColors.coral,
                              size: 17,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${item.city} · ${item.storeCount} 家门店 · ${item.routeCount} 条线路',
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
          );
        },
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.item});

  final GymDirectoryItem item;

  @override
  Widget build(BuildContext context) => Hero(
    tag: 'brand-${item.brandId}',
    child: Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WanpanColors.coralSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.logoUrl == null
          ? Text(
              item.brandName.characters.first,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: WanpanColors.coralStrong),
            )
          : Image.network(
              item.logoUrl!,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.landscape_rounded,
                color: WanpanColors.coral,
              ),
            ),
    ),
  );
}

class _CityButton extends StatelessWidget {
  const _CityButton({
    required this.value,
    required this.cities,
    required this.onChanged,
  });

  final String? value;
  final Set<String> cities;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String?>(
    tooltip: '切换城市',
    onSelected: onChanged,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    itemBuilder: (_) => [
      const PopupMenuItem(value: null, child: Text('全部城市')),
      ...cities.map((city) => PopupMenuItem(value: city, child: Text(city))),
    ],
    child: Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: WanpanColors.surfaceSoft,
        border: Border.all(color: WanpanColors.border),
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, size: 19),
          const SizedBox(width: 5),
          Text(value ?? '全国', style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    ),
  );
}
