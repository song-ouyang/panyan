import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/ranking_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/ranking_repository.dart';
import '../auth/application/session_controller.dart';
import '../gyms/application/home_city_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/motion/wanpan_motion_sound.dart';
import '../../shared/widgets/wanpan_lottie_stage.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({
    super.key,
    required this.api,
    required this.session,
    this.initialSegment = 0,
    this.motionSoundPlayer,
    this.cityController,
  });
  final ApiClient api;
  final SessionController session;
  final int initialSegment;
  final WanpanMotionSoundPlayer? motionSoundPlayer;
  final HomeCityController? cityController;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  late final RankingRepository _repository;
  late int _segment;
  bool _loading = true;
  String? _error;
  RankingBoard? _board;
  List<RankedRoute> _routes = const [];
  List<RankingRegion> _regions = const [];
  RankingRegion? _selectedRegion;
  String? _homeCity;
  bool _followsHomeCity = true;
  bool _regionsLoading = true;
  bool _regionsFailed = false;
  final Set<String> _shownEmptyAnimations = <String>{};
  String? _visibleEmptyAnimationKey;
  bool _visibleEmptyShouldPlay = false;
  int _emptyVisibilityReplayVersion = 0;
  int _loadRequestId = 0;
  bool _motionPreloadStarted = false;
  String? _observedSessionToken;
  late final WanpanMotionSoundPlayer _motionSoundPlayer;
  late final bool _ownsMotionSoundPlayer;
  bool _motionIsVisible = true;

  @override
  void initState() {
    super.initState();
    _repository = RankingRepository(widget.api);
    _ownsMotionSoundPlayer = widget.motionSoundPlayer == null;
    _motionSoundPlayer =
        widget.motionSoundPlayer ?? WanpanAssetMotionSoundPlayer();
    _segment = _normalizedSegment(widget.initialSegment);
    _observedSessionToken = widget.session.token;
    widget.session.addListener(_handleSessionChanged);
    _homeCity = widget.cityController?.city;
    _selectedRegion = _regionForCity(_homeCity);
    widget.cityController?.addListener(_handleHomeCityChanged);
    unawaited(_loadRegions());
    if (widget.cityController == null) _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.cityController?.initialize());
    });
  }

  @override
  void didUpdateWidget(covariant RankingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    var shouldReload = false;
    if (oldWidget.cityController != widget.cityController) {
      oldWidget.cityController?.removeListener(_handleHomeCityChanged);
      widget.cityController?.addListener(_handleHomeCityChanged);
      _homeCity = widget.cityController?.city;
      _followsHomeCity = true;
      _selectedRegion = _regionForCity(_homeCity);
      shouldReload = true;
      unawaited(widget.cityController?.initialize());
    }
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_handleSessionChanged);
      _observedSessionToken = widget.session.token;
      widget.session.addListener(_handleSessionChanged);
      shouldReload = true;
    }
    final requestedSegment = _normalizedSegment(widget.initialSegment);
    if (oldWidget.initialSegment != widget.initialSegment &&
        _segment != requestedSegment) {
      _segment = requestedSegment;
      shouldReload = true;
    }
    if (shouldReload) unawaited(_load());
  }

  @override
  void dispose() {
    _loadRequestId++;
    widget.session.removeListener(_handleSessionChanged);
    widget.cityController?.removeListener(_handleHomeCityChanged);
    if (_ownsMotionSoundPlayer) {
      unawaited(_motionSoundPlayer.dispose());
    } else {
      unawaited(_motionSoundPlayer.stop());
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasMotionVisible = _motionIsVisible;
    final motionIsVisible = TickerMode.of(context);
    if (wasMotionVisible && !motionIsVisible) {
      unawaited(_motionSoundPlayer.stop());
    }
    _motionIsVisible = motionIsVisible;
    if (!wasMotionVisible && motionIsVisible) {
      final emptyKey = _visibleEmptyAnimationKey;
      if (emptyKey != null) {
        _visibleEmptyShouldPlay = !_shownEmptyAnimations.contains(emptyKey);
        if (_visibleEmptyShouldPlay) _emptyVisibilityReplayVersion += 1;
      }
    }
    if (_motionPreloadStarted) return;
    _motionPreloadStarted = true;
    unawaited(
      preloadWanpanLottie(context, AppAssets.rankingEncouragementAnimation),
    );
    unawaited(
      _motionSoundPlayer.preload(const [
        WanpanMotionSoundCue.rankingEncouragement,
      ]),
    );
  }

  void _handleEmptyAnimationPresented(String emptyKey, bool animated) {
    if (!_motionIsVisible ||
        !TickerMode.of(context) ||
        emptyKey != _visibleEmptyAnimationKey) {
      return;
    }
    final firstPresentation = _shownEmptyAnimations.add(emptyKey);
    if (!animated || !firstPresentation) return;
    unawaited(
      _motionSoundPlayer.play(
        WanpanMotionSoundCue.rankingEncouragement,
        animated: true,
      ),
    );
  }

  Future<void> _load() async {
    final segment = _segment;
    final region = _selectedRegion;
    final requestId = ++_loadRequestId;
    setState(() {
      _loading = true;
      _error = null;
      _setVisibleEmptyAnimation(null);
    });
    if (region != null && region.province.isEmpty) {
      // A home city outside the directory has no rankings yet. Do not send an
      // invalid city-only query or silently replace it with the national board.
      if (_regionsLoading) return;
      setState(() {
        _loading = false;
        _board = null;
        _routes = const [];
        _error = _regionsFailed ? '榜单地区没有加载出来' : null;
        _setVisibleEmptyAnimation(
          _regionsFailed
              ? null
              : '${segment == 0 ? 'people' : 'routes'}-empty-${region.key}',
        );
      });
      return;
    }
    try {
      if (segment == 0) {
        final board = await _repository.getRanking(
          scope: region == null ? RankingScope.national : RankingScope.city,
          province: region?.province,
          city: region?.city,
        );
        if (!mounted || requestId != _loadRequestId || _segment != segment) {
          return;
        }
        setState(() {
          _board = board;
          _loading = false;
          _setVisibleEmptyAnimation(
            board.items.isEmpty
                ? 'people-empty-${region?.key ?? 'national'}'
                : null,
          );
        });
      } else {
        final routes = await _repository.getRankedRoutes(
          province: region?.province,
          city: region?.city,
        );
        if (!mounted || requestId != _loadRequestId || _segment != segment) {
          return;
        }
        setState(() {
          _routes = routes;
          _loading = false;
          _setVisibleEmptyAnimation(
            routes.isEmpty ? 'routes-empty-${region?.key ?? 'national'}' : null,
          );
        });
      }
    } catch (_) {
      if (!mounted || requestId != _loadRequestId || _segment != segment) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '榜单正在整理中';
        _setVisibleEmptyAnimation(null);
      });
    }
  }

  Future<void> _loadRegions() async {
    if (mounted) {
      setState(() {
        _regionsLoading = true;
        _regionsFailed = false;
      });
    }
    try {
      final regions = await _repository.getRegions();
      if (!mounted) return;
      final unique =
          <String, RankingRegion>{
            for (final region in regions) region.key: region,
          }.values.toList()..sort((a, b) {
            final cityOrder = a.city.compareTo(b.city);
            return cityOrder != 0
                ? cityOrder
                : a.province.compareTo(b.province);
          });
      final selectionStillExists =
          _selectedRegion == null || unique.contains(_selectedRegion);
      setState(() {
        _regions = unique;
        _regionsLoading = false;
        _regionsFailed = false;
        if (_followsHomeCity) {
          _selectedRegion = _regionForCity(_homeCity);
        } else if (!selectionStillExists) {
          _selectedRegion = null;
        }
      });
      if (widget.cityController != null || !selectionStillExists) {
        unawaited(_load());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _regionsLoading = false;
        _regionsFailed = true;
      });
      if (widget.cityController != null) unawaited(_load());
    }
  }

  RankingRegion? _regionForCity(String? city) {
    if (city == null) return null;
    final cityKey = city.trim().replaceFirst(RegExp(r'市$'), '');
    for (final region in _regions) {
      if (region.city.trim().replaceFirst(RegExp(r'市$'), '') == cityKey) {
        return region;
      }
    }
    return RankingRegion(province: '', city: city);
  }

  void _handleHomeCityChanged() {
    final city = widget.cityController?.city;
    if (!mounted || city == _homeCity) return;
    setState(() {
      _homeCity = city;
      _followsHomeCity = true;
      _selectedRegion = _regionForCity(city);
    });
    unawaited(_load());
  }

  void _handleSessionChanged() {
    final currentToken = widget.session.token;
    if (currentToken == _observedSessionToken) return;
    _observedSessionToken = currentToken;
    unawaited(_load());
  }

  void _changeSegment(int value) {
    if (_segment == value) return;
    setState(() => _segment = value);
    unawaited(_load());
  }

  void _changeRegion(RankingRegion? region) {
    _followsHomeCity = false;
    if (_selectedRegion == region) return;
    setState(() => _selectedRegion = region);
    unawaited(_load());
  }

  void _openRegionPicker() {
    if (_regionsFailed) {
      unawaited(_loadRegions());
      return;
    }
    if (_regionsLoading) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: WanpanColors.surface,
      showDragHandle: true,
      builder: (_) => _RegionPickerSheet(
        regions: _regions,
        selected: _selectedRegion,
        onSelected: _changeRegion,
      ),
    );
  }

  String get _regionLabel => _selectedRegion?.city ?? '全国';

  String get _regionKey => _selectedRegion?.key ?? 'national';

  static int _normalizedSegment(int value) => value == 1 ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('排行')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: _SegmentedControl(
              value: _segment,
              peopleLabel: _selectedRegion == null ? '全国榜' : '$_regionLabel榜',
              onChanged: _changeSegment,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _RegionFilter(
              selected: _selectedRegion,
              loading: _regionsLoading,
              failed: _regionsFailed,
              onPressed: _openRegionPicker,
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              child: _content(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const WanpanListSkeleton(key: ValueKey('loading'), itemCount: 4);
    }
    if (_error != null) {
      return Center(
        key: const ValueKey('error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_outlined,
              size: 52,
              color: WanpanColors.gold,
            ),
            const SizedBox(height: 12),
            Text(_error!, style: Theme.of(context).textTheme.titleMedium),
            TextButton(
              onPressed:
                  _regionsFailed && _selectedRegion?.province.isEmpty == true
                  ? _loadRegions
                  : _load,
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (_segment == 0) return _people();
    return _popularRoutes();
  }

  Widget _people() {
    final board = _board;
    if (board == null || board.items.isEmpty) {
      final emptyKey = 'people-empty-$_regionKey';
      return _RankingEmpty(
        key: ValueKey('$emptyKey-$_emptyVisibilityReplayVersion'),
        title: _selectedRegion == null ? '本月榜单刚刚开始' : '$_regionLabel榜正在等第一位岩友',
        description: _selectedRegion == null
            ? '完成一条线路，就能出现在这里。'
            : '在$_regionLabel完成一条线路，就能出现在这里。',
        actionLabel: widget.session.isAuthenticated ? '找线路打卡' : '登录后加入',
        playAnimation: _playsVisibleEmptyAnimation(emptyKey),
        onAnimationPresented: (animated) =>
            _handleEmptyAnimationPresented(emptyKey, animated),
        onAction: widget.session.isAuthenticated
            ? () => context.push('/routes/pick')
            : () => context.go('/login?from=/ranking'),
      );
    }
    return RefreshIndicator(
      key: const ValueKey('people'),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _ScoringCard(
            board: board,
            regionLabel: _regionLabel,
            isAuthenticated: widget.session.isAuthenticated,
          ),
          const SizedBox(height: 14),
          ...board.items.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RankTile(
                entry: entry,
                isMe: board.myRank?.user.id == entry.user.id,
                onTap: () => context.push('/users/${entry.user.id}'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _popularRoutes() {
    if (_routes.isEmpty) {
      final emptyKey = 'routes-empty-$_regionKey';
      return _RankingEmpty(
        key: ValueKey('$emptyKey-$_emptyVisibilityReplayVersion'),
        title: _selectedRegion == null ? '还没有热门线路' : '$_regionLabel还没有热门线路',
        description: '线路有真实完攀和点赞后，会进入$_regionLabel榜单。',
        actionLabel: _selectedRegion == null ? '去看看线路' : '换个城市看看',
        playAnimation: _playsVisibleEmptyAnimation(emptyKey),
        onAnimationPresented: (animated) =>
            _handleEmptyAnimationPresented(emptyKey, animated),
        onAction: _selectedRegion == null
            ? () => context.push('/routes/pick')
            : _openRegionPicker,
      );
    }
    return RefreshIndicator(
      key: const ValueKey('routes'),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _RouteRankingIntro(regionLabel: _regionLabel),
          const SizedBox(height: 12),
          for (var index = 0; index < _routes.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _RouteTile(
              rank: index + 1,
              route: _routes[index],
              onTap: () => context.push('/routes/${_routes[index].routeId}'),
            ),
          ],
        ],
      ),
    );
  }

  bool _playsVisibleEmptyAnimation(String key) =>
      _motionIsVisible &&
      _visibleEmptyAnimationKey == key &&
      _visibleEmptyShouldPlay;

  void _setVisibleEmptyAnimation(String? key) {
    if (key == null) {
      _visibleEmptyAnimationKey = null;
      _visibleEmptyShouldPlay = false;
      return;
    }
    if (_visibleEmptyAnimationKey == key) return;
    _visibleEmptyAnimationKey = key;
    _visibleEmptyShouldPlay = !_shownEmptyAnimations.contains(key);
  }
}

class _RegionFilter extends StatelessWidget {
  const _RegionFilter({
    required this.selected,
    required this.loading,
    required this.failed,
    required this.onPressed,
  });

  final RankingRegion? selected;
  final bool loading;
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = loading
        ? '地区加载中'
        : failed
        ? '地区加载失败 · 重试'
        : selected?.city ?? '全国';
    return WanpanPressable(
      key: const Key('ranking-region-button'),
      onTap: loading ? null : onPressed,
      semanticLabel: failed ? '地区加载失败，重新加载' : '筛选榜单区域，当前$label',
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: WanpanColors.skySoft,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(color: WanpanColors.sky.withValues(alpha: .72)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 20,
              color: WanpanColors.ink,
            ),
            const SizedBox(width: 8),
            Text('榜单区域', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: failed ? WanpanColors.danger : WanpanColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (loading)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                failed ? Icons.refresh_rounded : Icons.expand_more_rounded,
                color: failed ? WanpanColors.danger : WanpanColors.ink,
              ),
          ],
        ),
      ),
    );
  }
}

class _RegionPickerSheet extends StatefulWidget {
  const _RegionPickerSheet({
    required this.regions,
    required this.selected,
    required this.onSelected,
  });

  final List<RankingRegion> regions;
  final RankingRegion? selected;
  final ValueChanged<RankingRegion?> onSelected;

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RankingRegion> get _visibleRegions {
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

  void _select(RankingRegion? region) {
    widget.onSelected(region);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final regions = _visibleRegions;
    return AnimatedPadding(
      duration: WanpanMotion.duration(context, WanpanMotion.exit),
      curve: WanpanMotion.curve(context),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .78,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          children: [
            Text('选择榜单区域', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '看看不同城市正在流行哪些线路。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('ranking-region-search'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜索城市或省份',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _RegionOption(
              key: const Key('ranking-region-national'),
              label: '全国',
              description: '查看所有城市的榜单',
              selected: widget.selected == null,
              onTap: () => _select(null),
            ),
            for (final region in regions)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _RegionOption(
                  key: Key('ranking-region-${region.key}'),
                  label: region.city,
                  description: region.province == '待核验'
                      ? '查看该城市榜单'
                      : region.province,
                  selected: widget.selected == region,
                  onTap: () => _select(region),
                ),
              ),
            if (regions.isEmpty && _query.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('没有找到这个地区，换个关键词试试。', textAlign: TextAlign.center),
              ),
          ],
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
    super.key,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: WanpanPressable(
      onTap: onTap,
      semanticLabel: '$label，$description${selected ? '，已选择' : ''}',
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
              label == '全国'
                  ? Icons.public_rounded
                  : Icons.location_city_rounded,
              color: selected ? WanpanColors.sky : WanpanColors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
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
  );
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.value,
    required this.peopleLabel,
    required this.onChanged,
  });
  final int value;
  final String peopleLabel;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WanpanColors.surfaceSoft,
        borderRadius: BorderRadius.circular(WanpanRadii.pill),
      ),
      child: Row(
        children: [
          _segment(context, 0, peopleLabel),
          _segment(context, 1, '热门线路'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, int index, String label) {
    final active = value == index;
    return Expanded(
      child: Semantics(
        key: Key('ranking-segment-$index'),
        container: true,
        button: true,
        selected: active,
        label: label,
        onTap: () => onChanged(index),
        child: ExcludeSemantics(
          child: WanpanPressable(
            onTap: () => onChanged(index),
            pressedScale: .985,
            borderRadius: BorderRadius.circular(WanpanRadii.pill),
            child: AnimatedContainer(
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              curve: WanpanMotion.curve(context),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: active ? WanpanColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(WanpanRadii.pill),
                border: active ? Border.all(color: WanpanColors.border) : null,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? WanpanColors.ink : WanpanColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoringCard extends StatelessWidget {
  const _ScoringCard({
    required this.board,
    required this.regionLabel,
    required this.isAuthenticated,
  });
  final RankingBoard board;
  final String regionLabel;
  final bool isAuthenticated;
  @override
  Widget build(BuildContext context) {
    final me = board.myRank;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WanpanColors.coralSoft,
        borderRadius: BorderRadius.circular(WanpanRadii.large),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: WanpanColors.coral,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me == null
                      ? isAuthenticated
                            ? '完成线路，加入$regionLabel榜'
                            : '登录后加入$regionLabel榜'
                      : '我的$regionLabel排名 #${me.rank}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '完攀 +${board.scoring.completion} · 首攀 +${board.scoring.flash} · 点赞 +${board.scoring.like}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          if (me != null)
            Text(
              '${me.points}',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: WanpanColors.coralStrong),
            ),
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.entry,
    required this.isMe,
    required this.onTap,
  });
  final RankingEntry entry;
  final bool isMe;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: '查看${entry.user.nickname}的主页',
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isMe ? WanpanColors.coralSoft : WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(
            color: isMe ? const Color(0x59F2674F) : WanpanColors.border,
          ),
        ),
        child: Row(
          children: [
            _RankBadge(rank: entry.rank),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 21,
              backgroundColor: WanpanColors.surfaceSoft,
              backgroundImage: entry.user.avatarUrl == null
                  ? null
                  : NetworkImage(entry.user.avatarUrl!),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.user.nickname}${isMe ? ' · 我' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${entry.sendCount} 条完攀 · 最高 V${entry.maxGrade}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${entry.points}',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: WanpanColors.coralStrong),
                ),
                Text('积分', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final medalColor = switch (rank) {
      1 => WanpanColors.sunflower,
      2 => const Color(0xFF87969E),
      3 => const Color(0xFFB8794C),
      _ => null,
    };
    return Semantics(
      label: '第$rank名',
      excludeSemantics: true,
      child: SizedBox(
        width: 34,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (medalColor != null)
              Icon(Icons.emoji_events_rounded, size: 24, color: medalColor),
            Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WanpanColors.ink,
                fontSize: medalColor == null ? 19 : 12,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteRankingIntro extends StatelessWidget {
  const _RouteRankingIntro({required this.regionLabel});

  final String regionLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: WanpanColors.goldSoft,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      border: Border.all(color: WanpanColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WanpanColors.surface,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.emoji_events_rounded,
            color: WanpanColors.gold,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$regionLabel热门线路',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                '按完攀人数和点赞排序，点开可看线路详情',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.rank,
    required this.route,
    required this.onTap,
  });
  final int rank;
  final RankedRoute route;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final city = route.city?.trim();
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final metadata = <String>[
      if (city != null && city.isNotEmpty && !route.gymName.contains(city))
        city,
      route.gymName,
      ?route.wallZone,
    ].join(' · ');
    final grade = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: WanpanColors.coralSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          route.grade,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: WanpanColors.coralStrong),
        ),
      ),
    );
    final description = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$rank. ${route.routeName}',
            maxLines: usesLargeText ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            metadata,
            maxLines: usesLargeText ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
    final statistics = usesLargeText
        ? Text(
            '${route.completionCount} 人完攀  ·  ${route.totalLikes} 赞',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${route.completionCount} 人完攀',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                '${route.totalLikes} 赞',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          );
    const chevron = Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: WanpanColors.muted,
    );
    return WanpanPressable(
      key: Key('ranked-route-${route.routeId}'),
      onTap: onTap,
      semanticLabel:
          '第$rank名，${route.routeName}，${route.grade}，${route.completionCount}人完攀，查看线路详情',
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(color: WanpanColors.border),
        ),
        child: usesLargeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      grade,
                      const SizedBox(width: 13),
                      description,
                      const SizedBox(width: 4),
                      chevron,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: statistics),
                ],
              )
            : Row(
                children: [
                  grade,
                  const SizedBox(width: 13),
                  description,
                  statistics,
                  const SizedBox(width: 4),
                  chevron,
                ],
              ),
      ),
    );
  }
}

class _RankingEmpty extends StatelessWidget {
  const _RankingEmpty({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.playAnimation,
    required this.onAnimationPresented,
    required this.onAction,
  });
  final String title;
  final String description;
  final String actionLabel;
  final bool playAnimation;
  final WanpanLottiePresented onAnimationPresented;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              WanpanLottieStage(
                asset: AppAssets.rankingEncouragementAnimation,
                semanticLabel: '黑猫邀请你完成线路并加入排行榜',
                width: 236,
                height: 210,
                play: playAnimation,
                onPresented: onAnimationPresented,
                fallback: const WanpanMascot(
                  asset: AppAssets.mascotCelebrate,
                  width: 176,
                  height: 166,
                  radius: 38,
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: WanpanColors.inkSecondary),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: WanpanButton(
                  label: actionLabel,
                  icon: const Icon(Icons.route_rounded),
                  onPressed: onAction,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 17,
                    color: WanpanColors.sunflower,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '每一次真实完攀，都会点亮这里',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
