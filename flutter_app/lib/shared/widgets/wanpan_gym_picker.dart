import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../motion/wanpan_motion.dart';
import 'wanpan_pressable.dart';

/// A grouped gym picker shared by every flow that needs a concrete store.
///
/// The backend owns brand membership. This widget only presents the returned
/// hierarchy, so route creation and check-in never maintain competing client
/// side naming rules.
class WanpanGymPickerSheet extends StatefulWidget {
  const WanpanGymPickerSheet({
    required this.gyms,
    required this.selectedGymId,
    super.key,
  });

  final List<Gym> gyms;
  final String? selectedGymId;

  @override
  State<WanpanGymPickerSheet> createState() => _WanpanGymPickerSheetState();
}

class _WanpanGymPickerSheetState extends State<WanpanGymPickerSheet> {
  final _searchController = TextEditingController();
  final Set<String> _expandedBrandIds = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    final selected = widget.gyms
        .where((gym) => gym.id == widget.selectedGymId)
        .firstOrNull;
    if (selected != null) _expandedBrandIds.add(_brandKey(selected));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _brandKey(Gym gym) => gym.brandId ?? 'standalone:${gym.id}';

  String _brandName(Gym gym) => gym.brandName?.trim().isNotEmpty == true
      ? gym.brandName!.trim()
      : gym.name;

  List<_GymBrandGroup> get _groups {
    final byBrand = <String, List<Gym>>{};
    for (final gym in widget.gyms) {
      byBrand.putIfAbsent(_brandKey(gym), () => <Gym>[]).add(gym);
    }

    final query = _query.trim().toLowerCase();
    final groups = <_GymBrandGroup>[];
    for (final entry in byBrand.entries) {
      final allStores = [...entry.value]
        ..sort((a, b) {
          final city = a.city.compareTo(b.city);
          if (city != 0) return city;
          final district = (a.displayDistrict ?? '').compareTo(
            b.displayDistrict ?? '',
          );
          return district != 0 ? district : a.name.compareTo(b.name);
        });
      final name = _brandName(allStores.first);
      final visibleStores = query.isEmpty
          ? allStores
          : allStores
                .where((gym) {
                  final searchable = <String>[
                    name,
                    gym.name,
                    gym.city,
                    gym.province,
                    ?gym.displayDistrict,
                    gym.address,
                  ].join(' ').toLowerCase();
                  return searchable.contains(query);
                })
                .toList(growable: false);
      if (visibleStores.isEmpty) continue;
      groups.add(
        _GymBrandGroup(
          id: entry.key,
          name: name,
          isStandalone: allStores.first.brandId == null,
          allStoreCount: allStores.length,
          stores: visibleStores,
        ),
      );
    }
    groups.sort((a, b) => a.name.compareTo(b.name));
    return groups;
  }

  void _toggle(_GymBrandGroup group) {
    if (group.isStandalone) {
      Navigator.pop(context, group.stores.single.id);
      return;
    }
    setState(() {
      if (!_expandedBrandIds.add(group.id)) {
        _expandedBrandIds.remove(group.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final hasQuery = _query.trim().isNotEmpty;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            WanpanSpacing.page,
            4,
            WanpanSpacing.page,
            MediaQuery.viewInsetsOf(context).bottom + WanpanSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择岩馆',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: '搜索品牌、门店、城市或地址',
                  suffixIcon: _query.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空关键词',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${groups.length} 个岩馆品牌 · 选择后再进入具体门店',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: groups.isEmpty
                    ? const Center(child: Text('没有找到匹配的岩馆'))
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: WanpanSpacing.sm),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final expanded =
                              !group.isStandalone &&
                              (hasQuery ||
                                  _expandedBrandIds.contains(group.id) ||
                                  group.stores.any(
                                    (gym) => gym.id == widget.selectedGymId,
                                  ));
                          return _GymBrandCard(
                            group: group,
                            expanded: expanded,
                            selectedGymId: widget.selectedGymId,
                            onToggle: () => _toggle(group),
                            onSelected: (gymId) =>
                                Navigator.pop(context, gymId),
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

class _GymBrandGroup {
  const _GymBrandGroup({
    required this.id,
    required this.name,
    required this.isStandalone,
    required this.allStoreCount,
    required this.stores,
  });

  final String id;
  final String name;
  final bool isStandalone;
  final int allStoreCount;
  final List<Gym> stores;
}

class _GymBrandCard extends StatelessWidget {
  const _GymBrandCard({
    required this.group,
    required this.expanded,
    required this.selectedGymId,
    required this.onToggle,
    required this.onSelected,
  });

  final _GymBrandGroup group;
  final bool expanded;
  final String? selectedGymId;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final duration = WanpanMotion.duration(context, WanpanMotion.selection);
    return AnimatedContainer(
      duration: duration,
      curve: WanpanMotion.curve(context),
      decoration: BoxDecoration(
        color: WanpanColors.surface,
        border: Border.all(
          color: expanded ? WanpanColors.coralSoft : WanpanColors.border,
          width: expanded ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          WanpanPressable(
            semanticLabel: group.isStandalone
                ? '选择${group.name}'
                : '${expanded ? '收起' : '展开'}${group.name}的${group.allStoreCount}家门店',
            onTap: onToggle,
            borderRadius: BorderRadius.circular(WanpanRadii.medium),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WanpanColors.coralSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.landscape_rounded,
                      color: WanpanColors.coralStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.isStandalone
                              ? '独立岩馆'
                              : '${group.allStoreCount} 家门店',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: duration,
                    curve: WanpanMotion.curve(context),
                    child: Icon(
                      group.isStandalone
                          ? Icons.chevron_right_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: WanpanColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded && !group.isStandalone)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: WanpanColors.border)),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < group.stores.length; index++)
                    _GymStoreRow(
                      gym: group.stores[index],
                      selected: group.stores[index].id == selectedGymId,
                      showDivider: index < group.stores.length - 1,
                      onTap: () => onSelected(group.stores[index].id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GymStoreRow extends StatelessWidget {
  const _GymStoreRow({
    required this.gym,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final Gym gym;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanPressable(
    semanticLabel: '选择门店${gym.name}',
    onTap: onTap,
    borderRadius: BorderRadius.zero,
    child: Container(
      margin: const EdgeInsets.only(left: 70),
      padding: const EdgeInsets.fromLTRB(0, 11, 12, 11),
      decoration: BoxDecoration(
        color: selected
            ? WanpanColors.coralSoft.withValues(alpha: .42)
            : Colors.transparent,
        border: showDivider
            ? const Border(bottom: BorderSide(color: WanpanColors.border))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gym.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  <String>[
                    gym.city,
                    ?gym.displayDistrict,
                    '${gym.routeCount} 条线路',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            color: selected ? WanpanColors.coral : WanpanColors.muted,
          ),
        ],
      ),
    ),
  );
}
