import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import 'wanpan_pressable.dart';

@immutable
class WanpanRegion {
  const WanpanRegion({required this.province, required this.city});

  final String province;
  final String city;

  String get key => '$province/$city';

  @override
  bool operator ==(Object other) =>
      other is WanpanRegion && other.province == province && other.city == city;

  @override
  int get hashCode => Object.hash(province, city);
}

class WanpanRegionPickerSheet extends StatefulWidget {
  const WanpanRegionPickerSheet({
    required this.regions,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<WanpanRegion> regions;
  final WanpanRegion? selected;
  final ValueChanged<WanpanRegion?> onSelected;

  @override
  State<WanpanRegionPickerSheet> createState() =>
      _WanpanRegionPickerSheetState();
}

class _WanpanRegionPickerSheetState extends State<WanpanRegionPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WanpanRegion> get _visibleRegions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.regions;
    return widget.regions
        .where(
          (region) =>
              region.city.toLowerCase().contains(query) ||
              region.province.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  void _select(WanpanRegion? region) {
    final navigator = Navigator.of(context);
    widget.onSelected(region);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final regions = _visibleRegions;
    // The padding reduces the available height once; the scroll view keeps
    // every control reachable on compact screens while the keyboard is open.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .82,
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '选择地区',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: '关闭地区选择',
                            icon: const Icon(Icons.close_rounded),
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('gym-region-search'),
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: '搜索省份或城市',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _RegionOption(
                        key: const Key('gym-region-option-national'),
                        label: '全国',
                        description: '查看所有地区的岩馆',
                        national: true,
                        selected: widget.selected == null,
                        onTap: () => _select(null),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                sliver: regions.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _query.trim().isEmpty
                                ? '暂无可选地区，可以查看全国岩馆。'
                                : '没有找到这个地区，换个关键词试试。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : SliverList.separated(
                        itemCount: regions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final region = regions[index];
                          final province = region.province.trim();
                          return _RegionOption(
                            key: Key('gym-region-option-${region.key}'),
                            label: region.city,
                            description: province.isEmpty || province == '待核验'
                                ? null
                                : province,
                            selected: widget.selected == region,
                            onTap: () => _select(region),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionOption extends StatelessWidget {
  const _RegionOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
    this.national = false,
    super.key,
  });

  final String label;
  final String? description;
  final bool selected;
  final bool national;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: description == null ? label : '$label，$description',
    onTap: onTap,
    child: ExcludeSemantics(
      child: WanpanPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? WanpanColors.skySoft : WanpanColors.surface,
            borderRadius: BorderRadius.circular(WanpanRadii.medium),
            border: Border.all(
              color: selected ? WanpanColors.sky : WanpanColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                national ? Icons.public_rounded : Icons.location_city_rounded,
                color: selected ? WanpanColors.sky : WanpanColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    if (description != null)
                      Text(
                        description!,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: WanpanColors.sky)
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WanpanColors.muted,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
