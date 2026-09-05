import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/network/api_client.dart';
import '../../core/preferences/gym_selection_store.dart';
import '../../core/repositories/gym_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';
import 'map_navigation.dart';

class GymScreen extends StatefulWidget {
  const GymScreen({
    required this.api,
    required this.gymId,
    super.key,
    this.gymRepository,
    this.selectionStore,
    this.mapNavigationLauncher = const DeviceMapNavigationLauncher(),
  });

  final ApiClient api;
  final String gymId;
  final GymRepository? gymRepository;
  final GymSelectionStore? selectionStore;
  final MapNavigationLauncher mapNavigationLauncher;

  @override
  State<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends State<GymScreen> {
  late final GymRepository _repository;
  final _routeSearchController = TextEditingController();
  GymDetail? _detail;
  List<ClimbingRoute> _routes = const [];
  String _routeQuery = '';
  String? _grade;
  String? _routeSetId;
  Object? _error;
  bool _loading = true;
  int _requestId = 0;
  bool _hasLoadedGym = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.gymRepository ?? GymRepository(widget.api);
    widget.api.climbingActivity.addListener(_handleActivityChanged);
    _loadAll();
  }

  @override
  void dispose() {
    widget.api.climbingActivity.removeListener(_handleActivityChanged);
    _routeSearchController.dispose();
    super.dispose();
  }

  void _handleActivityChanged() {
    if (mounted) _loadAll();
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
      if (!_hasLoadedGym) {
        _hasLoadedGym = true;
        await _rememberOpenedGym(_detail!.gym, requestId);
      }
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error);
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _rememberOpenedGym(Gym gym, int requestId) async {
    if (!mounted ||
        requestId != _requestId ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    try {
      final store = widget.selectionStore ?? await GymSelectionStore.load();
      if (!mounted ||
          requestId != _requestId ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await store.rememberGym(gym);
    } catch (_) {
      // Preference failures must not hide a successfully loaded gym.
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

  Future<void> _showNavigation(Gym gym) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: WanpanColors.surface,
    showDragHandle: true,
    builder: (_) => _MapNavigationSheet(
      launcher: widget.mapNavigationLauncher,
      target: MapNavigationTarget(
        name: gym.name,
        city: gym.city,
        address: gym.address,
        latitude: gym.latitude,
        longitude: gym.longitude,
      ),
    ),
  );

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
          SliverToBoxAdapter(
            child: _GymHeader(
              gym: detail.gym,
              onNavigate: () => _showNavigation(detail.gym),
            ),
          ),
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
                color: WanpanColors.grapeSoft,
                borderColor: WanpanColors.grape.withValues(alpha: .38),
                semanticLabel: '在${detail.gym.name}发布新线路',
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 124,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 18,
                        top: 28,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(
                            Icons.gesture_rounded,
                            color: WanpanColors.grape,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 84,
                        top: 31,
                        child: Text(
                          '标记并发布新线路',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Positioned(
                        left: 84,
                        top: 61,
                        child: Text(
                          '岩馆已选好，拍照标点后立即发布',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: -16,
                        width: 146,
                        height: 104,
                        child: Image.asset(
                          AppAssets.routeMapCat,
                          cacheWidth: 520,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      const Positioned(
                        right: 10,
                        top: 47,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: WanpanColors.grape,
                        ),
                      ),
                    ],
                  ),
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
  const _GymHeader({required this.gym, required this.onNavigate});

  final Gym gym;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                gym.name,
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(fontSize: 31),
              ),
            ),
            if (gym.verified)
              const Icon(Icons.verified_rounded, color: WanpanColors.coral),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  gym.locationLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: '选择地图导航到${gym.name}',
              excludeFromSemantics: true,
              child: WanpanPressable(
                key: const Key('gym-navigation-button'),
                onTap: onNavigate,
                semanticLabel: '导航到${gym.name}，选择地图',
                enableHaptics: true,
                borderRadius: BorderRadius.circular(WanpanRadii.pill),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 76,
                    minHeight: 44,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: WanpanColors.skySoft,
                    borderRadius: BorderRadius.circular(WanpanRadii.pill),
                    border: Border.all(
                      color: WanpanColors.sky.withValues(alpha: .72),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        size: 18,
                        color: WanpanColors.ink,
                      ),
                      SizedBox(width: 5),
                      Text(
                        '导航',
                        style: TextStyle(
                          color: WanpanColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MapNavigationSheet extends StatefulWidget {
  const _MapNavigationSheet({required this.launcher, required this.target});

  final MapNavigationLauncher launcher;
  final MapNavigationTarget target;

  @override
  State<_MapNavigationSheet> createState() => _MapNavigationSheetState();
}

class _MapNavigationSheetState extends State<_MapNavigationSheet> {
  static const _primaryApps = <MapNavigationApp>[
    MapNavigationApp.amap,
    MapNavigationApp.tencent,
    MapNavigationApp.baidu,
    MapNavigationApp.system,
  ];

  late final Future<List<MapNavigationApp>> _apps = _loadApps();
  MapNavigationApp? _opening;
  String? _error;
  bool _showWebFallback = false;

  Future<List<MapNavigationApp>> _loadApps() async {
    try {
      final apps = await widget.launcher.availableApps(widget.target);
      return apps.isEmpty ? const [MapNavigationApp.web] : apps;
    } catch (_) {
      return const [MapNavigationApp.web];
    }
  }

  Future<void> _open(MapNavigationApp app, {required bool hasSystemMap}) async {
    if (_opening != null) return;
    final route = ModalRoute.of(context);
    setState(() {
      _opening = app;
      _error = null;
    });
    final opened = await widget.launcher.open(app, widget.target);
    if (!mounted || route?.isCurrent != true) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _opening = null;
      _showWebFallback = true;
      final label = app.label(widget.launcher.currentPlatform);
      _error = app == MapNavigationApp.web
          ? '没有打开网页地图，请检查浏览器设置后重试。'
          : app == MapNavigationApp.system
          ? '没有打开$label，可以改用下方网页地图。'
          : '没有打开$label，可能尚未安装或暂不可用，${hasSystemMap ? '可以改用系统地图。' : '可以使用下方网页地图。'}';
    });
  }

  void _explainUnavailable(MapNavigationApp app, {required bool hasSystemMap}) {
    setState(() {
      _showWebFallback = !hasSystemMap;
      final label = app.label(widget.launcher.currentPlatform);
      _error = app == MapNavigationApp.system
          ? '这台手机暂时没有可用的系统地图，可以使用下方网页地图。'
          : '$label尚未安装或暂不可用，${hasSystemMap ? '可以改用系统地图。' : '可以使用下方网页地图。'}';
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        key: const Key('map-navigation-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('选择导航地图', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '从当前位置前往 ${widget.target.name}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '常用地图都列在这里；显示“不可用”时，可改用系统地图。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          FutureBuilder<List<MapNavigationApp>>(
            future: _apps,
            builder: (context, snapshot) {
              final apps = snapshot.data;
              if (apps == null) {
                return const SizedBox(
                  height: 104,
                  child: Center(
                    child: CircularProgressIndicator(color: WanpanColors.coral),
                  ),
                );
              }
              final availableApps = apps.toSet();
              final hasSystemMap = availableApps.contains(
                MapNavigationApp.system,
              );
              final showWebFallback =
                  availableApps.contains(MapNavigationApp.web) ||
                  !hasSystemMap ||
                  _showWebFallback;
              final usableApps = <MapNavigationApp>{
                ...availableApps,
                if (showWebFallback) MapNavigationApp.web,
              };
              final options = <MapNavigationApp>[
                ..._primaryApps,
                if (showWebFallback) MapNavigationApp.web,
              ];
              return Column(
                children: [
                  for (var index = 0; index < options.length; index++) ...[
                    if (index > 0) const SizedBox(height: 10),
                    _MapNavigationOption(
                      app: options[index],
                      platform: widget.launcher.currentPlatform,
                      available: usableApps.contains(options[index]),
                      loading: _opening == options[index],
                      enabled: _opening == null,
                      onTap: () => usableApps.contains(options[index])
                          ? _open(options[index], hasSystemMap: hasSystemMap)
                          : _explainUnavailable(
                              options[index],
                              hasSystemMap: hasSystemMap,
                            ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('map-navigation-error'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: WanpanColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MapNavigationOption extends StatelessWidget {
  const _MapNavigationOption({
    required this.app,
    required this.platform,
    required this.available,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final MapNavigationApp app;
  final TargetPlatform platform;
  final bool available;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  ({IconData icon, Color color, Color softColor, String description})
  get _style => switch (app) {
    MapNavigationApp.amap => (
      icon: Icons.near_me_rounded,
      color: WanpanColors.sky,
      softColor: WanpanColors.skySoft,
      description: '打开高德并规划驾车路线',
    ),
    MapNavigationApp.tencent => (
      icon: Icons.route_rounded,
      color: WanpanColors.grape,
      softColor: WanpanColors.grapeSoft,
      description: '打开腾讯地图规划驾车路线',
    ),
    MapNavigationApp.baidu => (
      icon: Icons.navigation_rounded,
      color: WanpanColors.coral,
      softColor: WanpanColors.coralSoft,
      description: '打开百度地图开始导航',
    ),
    MapNavigationApp.system => (
      icon: Icons.map_rounded,
      color: WanpanColors.success,
      softColor: WanpanColors.mintSoft,
      description: platform == TargetPlatform.iOS ? '使用系统地图规划路线' : '交给手机里的其他地图',
    ),
    MapNavigationApp.web => (
      icon: Icons.public_rounded,
      color: WanpanColors.inkSecondary,
      softColor: WanpanColors.surfaceMuted,
      description: '未安装地图 App 时查看网页路线',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final description = available
        ? style.description
        : app == MapNavigationApp.system
        ? '系统地图不可用，可使用网页地图'
        : '未安装或暂不可用，点按查看说明';
    return WanpanPressable(
      key: Key('map-navigation-${app.name}'),
      onTap: enabled ? onTap : null,
      semanticLabel:
          '${app.label(platform)}，${available ? style.description : description}',
      enableHaptics: true,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(color: WanpanColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: style.softColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(style.icon, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    app.label(platform),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: WanpanColors.coral,
                ),
              )
            else if (!available)
              Text(
                '不可用',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: WanpanColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              const Icon(
                Icons.open_in_new_rounded,
                size: 20,
                color: WanpanColors.muted,
              ),
          ],
        ),
      ),
    );
  }
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
            Text('本轮线路', style: Theme.of(context).textTheme.headlineMedium),
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
                    color: WanpanColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: WanpanColors.border),
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
            fillColor: WanpanColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WanpanRadii.medium),
              borderSide: const BorderSide(color: WanpanColors.sky, width: 1.5),
            ),
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
  Widget build(BuildContext context) {
    final routeColor = _routeColor(route.grade);
    return WanpanCard(
      onTap: onTap,
      semanticLabel: '打开${route.name}',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: SizedBox(
        height: 76,
        child: Row(
          children: [
            CustomPaint(
              painter: _HoldPainter(
                front: routeColor.front,
                depth: routeColor.depth,
              ),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Text(
                    route.grade,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: routeColor.ink, fontSize: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
            Container(
              width: 26,
              height: 18,
              decoration: BoxDecoration(
                color: routeColor.front,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(10),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(15),
                ),
                border: Border.all(color: routeColor.depth, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: WanpanColors.coral),
          ],
        ),
      ),
    );
  }
}

class _HoldPainter extends CustomPainter {
  const _HoldPainter({required this.front, required this.depth});

  final Color front;
  final Color depth;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Path()
      ..moveTo(size.width * .18, size.height * .23)
      ..quadraticBezierTo(
        size.width * .49,
        0,
        size.width * .77,
        size.height * .18,
      )
      ..quadraticBezierTo(
        size.width,
        size.height * .44,
        size.width * .84,
        size.height * .79,
      )
      ..quadraticBezierTo(
        size.width * .45,
        size.height,
        size.width * .12,
        size.height * .72,
      )
      ..quadraticBezierTo(
        0,
        size.height * .44,
        size.width * .18,
        size.height * .23,
      )
      ..close();
    canvas.drawPath(shadow.shift(const Offset(0, 5)), Paint()..color = depth);
    canvas.drawPath(shadow, Paint()..color = front);
    canvas.drawCircle(
      Offset(size.width * .71, size.height * .22),
      5,
      Paint()..color = depth,
    );
    canvas.drawCircle(
      Offset(size.width * .71, size.height * .22),
      2.3,
      Paint()..color = WanpanColors.surface,
    );
  }

  @override
  bool shouldRepaint(_HoldPainter oldDelegate) =>
      oldDelegate.front != front || oldDelegate.depth != depth;
}

({Color front, Color depth, Color ink}) _routeColor(String grade) {
  final digits = RegExp(r'\d+').firstMatch(grade)?.group(0);
  final level = int.tryParse(digits ?? '') ?? 0;
  return switch (level % 5) {
    0 => (
      front: WanpanColors.sky,
      depth: const Color(0xFF3FA8CC),
      ink: WanpanColors.ink,
    ),
    1 => (
      front: WanpanColors.mint,
      depth: const Color(0xFF6CB889),
      ink: WanpanColors.ink,
    ),
    2 => (
      front: WanpanColors.sunflower,
      depth: const Color(0xFFDFA721),
      ink: WanpanColors.ink,
    ),
    3 => (
      front: WanpanColors.coral,
      depth: WanpanColors.coralStrong,
      ink: Colors.white,
    ),
    _ => (
      front: WanpanColors.grape,
      depth: const Color(0xFF7655C5),
      ink: Colors.white,
    ),
  };
}
