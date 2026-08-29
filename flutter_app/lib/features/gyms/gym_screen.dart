import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/gym_repository.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';

class GymScreen extends StatefulWidget {
  const GymScreen({required this.api, required this.gymId, super.key});

  final ApiClient api;
  final String gymId;

  @override
  State<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends State<GymScreen> {
  late final GymRepository _repository = GymRepository(widget.api);
  final _routeSearchController = TextEditingController();
  GymDetail? _detail;
  List<ClimbingRoute> _routes = const [];
  String _routeQuery = '';
  String? _grade;
  String? _routeSetId;
  Object? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _routeSearchController.dispose();
    super.dispose();
  }

  List<ClimbingRoute> get _visibleRoutes {
    final query = _routeQuery.trim().toLowerCase();
    if (query.isEmpty) return _routes;
    return _routes
        .where((route) {
          final searchable = <String>[
            route.name,
            route.grade,
            route.color,
            if (route.wallZone != null) route.wallZone!,
            if (route.setterName != null) route.setterName!,
            if (route.routeSetName != null) route.routeSetName!,
          ].join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _loadAll() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _repository.getGym(widget.gymId),
        _repository.getRoutes(
          widget.gymId,
          grade: _grade,
          routeSetId: _routeSetId,
        ),
      ]);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _detail = results[0] as GymDetail;
        _routes = results[1] as List<ClimbingRoute>;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error);
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRoutes() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final routes = await _repository.getRoutes(
        widget.gymId,
        grade: _grade,
        routeSetId: _routeSetId,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() => _routes = routes);
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error);
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitRoute() async {
    final created = await context.push<bool>(
      '/route-submissions/new?gymId=${Uri.encodeQueryComponent(widget.gymId)}',
    );
    if (created == true && mounted) await _loadAll();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_detail?.gym.name ?? '线路'),
      actions: [
        IconButton(
          tooltip: '快速找线路打卡',
          onPressed: () => context.push(
            '/routes/pick?gymId=${Uri.encodeQueryComponent(widget.gymId)}',
          ),
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: '发布新线路',
          onPressed: _submitRoute,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: _body(),
  );

  Widget _body() {
    final detail = _detail;
    if (detail == null && _loading) {
      return const WanpanListSkeleton(itemCount: 4);
    }
    if (detail == null) {
      return WanpanErrorState(title: '岩馆详情没有加载出来', onRetry: _loadAll);
    }
    final visibleRoutes = _visibleRoutes;
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: WanpanColors.coral,
      child: CustomScrollView(
        key: PageStorageKey('gym-${widget.gymId}'),
        slivers: [
          SliverToBoxAdapter(child: _GymHeader(gym: detail.gym)),
          SliverToBoxAdapter(
            child: _Filters(
              routeSets: detail.routeSets,
              selectedGrade: _grade,
              selectedRouteSetId: _routeSetId,
              searchController: _routeSearchController,
              searchQuery: _routeQuery,
              resultCount: visibleRoutes.length,
              onSearchChanged: (value) => setState(() => _routeQuery = value),
              onSearchCleared: () {
                _routeSearchController.clear();
                setState(() => _routeQuery = '');
              },
              onGradeChanged: (value) {
                if (_grade == value) return;
                setState(() => _grade = value);
                _loadRoutes();
              },
              onRouteSetChanged: (value) {
                if (_routeSetId == value) return;
                setState(() => _routeSetId = value);
                _loadRoutes();
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: WanpanCard(
                onTap: _submitRoute,
                color: WanpanColors.coralSoft,
                borderColor: Colors.transparent,
                semanticLabel: '在${detail.gym.name}发布新线路',
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: WanpanColors.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.gesture_rounded,
                        color: WanpanColors.coral,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '标记并发布新线路',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '岩馆已选好，拍照标点后立即发布',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: WanpanColors.coral,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loading && _routes.isNotEmpty)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null && _routes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: WanpanErrorState(title: '线路没有加载出来', onRetry: _loadRoutes),
            )
          else if (!_loading && visibleRoutes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: WanpanEmptyState(
                title: _routeQuery.trim().isEmpty ? '这一组还没有线路' : '没找到这条线路',
                description: _routeQuery.trim().isEmpty
                    ? '换个难度或线路周期看看。'
                    : '试试线路名、颜色、难度或墙面区域。',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 44),
              sliver: SliverList.separated(
                itemCount: visibleRoutes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _RouteCard(
                  route: visibleRoutes[index],
                  onTap: () =>
                      context.push('/routes/${visibleRoutes[index].id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GymHeader extends StatelessWidget {
  const _GymHeader({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gym.coverUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 16 / 8,
              child: Image.network(
                gym.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: WanpanColors.surfaceSoft,
                  child: Icon(Icons.landscape_rounded, size: 52),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                gym.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (gym.verified)
              const Icon(Icons.verified_rounded, color: WanpanColors.coral),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${gym.city}${gym.district == null ? '' : ' · ${gym.district}'} · ${gym.address}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.routeSets,
    required this.selectedGrade,
    required this.selectedRouteSetId,
    required this.searchController,
    required this.searchQuery,
    required this.resultCount,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onGradeChanged,
    required this.onRouteSetChanged,
  });

  final List<RouteSet> routeSets;
  final String? selectedGrade;
  final String? selectedRouteSetId;
  final TextEditingController searchController;
  final String searchQuery;
  final int resultCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<String?> onGradeChanged;
  final ValueChanged<String?> onRouteSetChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(
          children: [
            Text('本轮线路', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (routeSets.isNotEmpty)
              PopupMenuButton<String?>(
                tooltip: '切换线路周期',
                onSelected: onRouteSetChanged,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('全部周期')),
                  ...routeSets.map(
                    (set) =>
                        PopupMenuItem(value: set.id, child: Text(set.name)),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: WanpanColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Text(
                        routeSets
                                .where((set) => set.id == selectedRouteSetId)
                                .firstOrNull
                                ?.name ??
                            '全部周期',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: '输入线路名、颜色或墙区',
            suffixIcon: searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: '清空线路筛选',
                    onPressed: onSearchCleared,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
      if (searchQuery.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 20, 0),
          child: Text(
            '找到 $resultCount 条，点击线路即可查看并发布视频',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: WanpanColors.coralStrong),
          ),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
        child: Row(
          children: [
            _GradeChip(
              label: '全部',
              selected: selectedGrade == null,
              onTap: () => onGradeChanged(null),
            ),
            for (var level = 0; level <= 8; level++) ...[
              const SizedBox(width: 8),
              _GradeChip(
                label: 'V$level',
                selected: selectedGrade == 'V$level',
                onTap: () => onGradeChanged('V$level'),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    onPressed: onTap,
    backgroundColor: selected ? WanpanColors.ink : WanpanColors.surfaceSoft,
    side: BorderSide(color: selected ? WanpanColors.ink : WanpanColors.border),
    labelStyle: Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: selected ? Colors.white : WanpanColors.inkSecondary),
    shape: const StadiumBorder(),
  );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.onTap});

  final ClimbingRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    semanticLabel: '打开${route.name}',
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WanpanColors.coral,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: WanpanColors.coralStrong, offset: Offset(0, 4)),
            ],
          ),
          child: Text(
            route.grade,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(route.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                [
                  if (route.wallZone != null) route.wallZone!,
                  '${route.sendCount} 人完攀',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: WanpanColors.coral),
      ],
    ),
  );
}
