import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/gym_repository.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';
import '../auth/application/session_controller.dart';
import '../notifications/application/notifications_controller.dart';
import 'application/home_city_controller.dart';
import 'application/weekly_route_preview_data.dart' as weekly_preview;
import 'weekly_gym_preview.dart';

class GymsScreen extends StatefulWidget {
  const GymsScreen({
    required this.api,
    required this.session,
    this.cityController,
    this.notificationsController,
    this.useWeeklyRouteMocks = weekly_preview.useWeeklyRouteMocks,
    super.key,
  });

  final ApiClient api;
  final SessionController session;
  final HomeCityController? cityController;
  final NotificationsController? notificationsController;
  final bool useWeeklyRouteMocks;

  @override
  State<GymsScreen> createState() => _GymsScreenState();
}

class _GymsScreenState extends State<GymsScreen> {
  late final GymRepository _repository = GymRepository(widget.api);
  late final ProfileRepository _profileRepository = ProfileRepository(
    widget.api,
  );
  late final HomeCityController _cityController =
      widget.cityController ?? HomeCityController();
  final _cityOptions = ValueNotifier<List<String>>(const []);
  List<GymDirectoryItem> _items = const [];
  List<GymDirectoryItem> _globalItems = const [];
  List<ClimbingRoute> _weeklyRoutes = const [];
  List<weekly_preview.WeeklyGymPreview> _weeklyGyms = const [];
  int _weeklyRequestId = 0;
  UserProfile? _profile;
  String? _city;
  Object? _error;
  bool _loading = true;
  int _requestId = 0;
  String? _sessionUserId;

  @override
  void initState() {
    super.initState();
    _city = _cityController.city;
    _sessionUserId = widget.session.user?.id;
    widget.session.addListener(_onSessionChanged);
    widget.api.climbingActivity.addListener(_onActivityChanged);
    _cityController.addListener(_onCityChanged);
    widget.notificationsController?.addListener(_onNotificationsChanged);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_cityController.initialize());
    });
  }

  @override
  void dispose() {
    _cityController.removeListener(_onCityChanged);
    widget.notificationsController?.removeListener(_onNotificationsChanged);
    widget.session.removeListener(_onSessionChanged);
    widget.api.climbingActivity.removeListener(_onActivityChanged);
    if (widget.cityController == null) _cityController.dispose();
    _cityOptions.dispose();
    super.dispose();
  }

  void _onActivityChanged() {
    if (!mounted) return;
    _globalItems = const [];
    unawaited(_load());
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openNotifications() async {
    await context.push('/notifications');
    if (mounted) await widget.notificationsController?.refresh();
  }

  void _onSessionChanged() {
    final userId = widget.session.user?.id;
    if (userId == _sessionUserId) return;
    _sessionUserId = userId;
    _profile = null;
    _onActivityChanged();
  }

  void _onCityChanged() {
    if (!mounted) return;
    final changed = _city != _cityController.city;
    setState(() {
      _city = _cityController.city;
      if (changed) _items = const [];
    });
    if (changed) unawaited(_load());
  }

  Future<UserProfile?> _tryLoadProfile() async {
    if (!widget.session.isAuthenticated) return null;
    try {
      return await _profileRepository.getMe();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    await Future.wait([_loadDirectory(), _loadWeekly()]);
  }

  Future<void> _loadWeekly() async {
    final requestId = ++_weeklyRequestId;
    final city = _city;
    if (widget.useWeeklyRouteMocks) {
      setState(() {
        _weeklyRoutes = const [];
        _weeklyGyms = weekly_preview.weeklyGymPreviewData(city: city);
      });
      return;
    }
    setState(() {
      _weeklyRoutes = const [];
      _weeklyGyms = const [];
    });
    try {
      final routes = await _repository.getWeeklyRoutes(city: city);
      if (!mounted || requestId != _weeklyRequestId) return;
      setState(() => _weeklyRoutes = routes);
    } catch (_) {
      // Keep this optional section hidden until a later refresh returns routes.
    }
  }

  Future<void> _publishRoute() async {
    await context.push('/route-submissions/new');
    if (mounted) await _load();
  }

  Future<void> _openWeeklyRoute(ClimbingRoute route) async {
    await context.push('/routes/${route.id}');
    if (mounted) await _loadWeekly();
  }

  Future<void> _openWeeklyGym(weekly_preview.WeeklyGymPreview gym) async {
    if (gym.gymId case final gymId?) {
      await context.push('/gyms/$gymId');
    } else if (gym.brandId case final brandId?) {
      await context.push(
        Uri(
          path: '/brands/$brandId',
          queryParameters: {'city': gym.city},
        ).toString(),
      );
    } else {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => PendingGymInformationScreen(gym: gym),
        ),
      );
    }
  }

  Future<void> _loadDirectory() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final profileFuture = _tryLoadProfile();
    final directoryFuture = _repository.getDirectory(city: _city);
    final globalDirectoryFuture = _city == null
        ? directoryFuture
        : _globalItems.isEmpty
        ? _repository.getDirectory()
        : Future.value(_globalItems);
    try {
      final (items, globalItems, profile) = await (
        directoryFuture,
        globalDirectoryFuture,
        profileFuture,
      ).wait;
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = items;
        _globalItems = globalItems;
        _profile = profile;
      });
      _cityOptions.value = _cities;
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error);
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  List<String> get _cities {
    final cities = _globalItems
        .expand((item) => item.availableCities)
        .toSet()
        .toList(growable: false);
    return cities..sort();
  }

  String _brandPath(GymDirectoryItem item, {required String? city}) => Uri(
    path: '/brands/${item.brandId}',
    queryParameters: city == null ? null : {'city': city},
  ).toString();

  Future<void> _showDirectory() async {
    final selected = await showModalBottomSheet<_GymDirectorySelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GymDirectorySheet(
        repository: _repository,
        initialItems: _items,
        globalItems: _globalItems,
        cities: _cities,
        initialCity: _city,
      ),
    );
    if (selected != null && mounted) {
      await context.push(_brandPath(selected.item, city: selected.city));
    }
  }

  Future<void> _showCityPicker() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) =>
        _CityPickerSheet(cities: _cityOptions, controller: _cityController),
  );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: WanpanColors.coral,
          child: CustomScrollView(
            key: const PageStorageKey('gym-home'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
                sliver: SliverList.list(
                  children: [
                    _HomeHeader(
                      city: _city,
                      locating: _cityController.isLocating,
                      onChooseCity: _showCityPicker,
                      onNotifications: _openNotifications,
                      unreadCount:
                          widget.notificationsController?.unreadCount ?? 0,
                    ),
                    if (_cityController.locationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_off_rounded,
                              size: 16,
                              color: WanpanColors.muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '暂未获取位置，可手动选择城市',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: _showCityPicker,
                              child: const Text('选择城市'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    _MonthlyProgress(profile: _profile),
                    const SizedBox(height: 18),
                    const _HomeSectionTitle(title: '快捷开始'),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickStartCard(
                            label: '找岩馆',
                            color: Color(0xFFA7E5F4),
                            borderColor: Color(0xFF43AED2),
                            icon: Icons.cottage_rounded,
                            onTap: _showDirectory,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickStartCard(
                            label: '发布线路',
                            color: Color(0xFFD8C5FF),
                            borderColor: WanpanColors.grape,
                            icon: Icons.edit_note_rounded,
                            onTap: _publishRoute,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickStartCard(
                            label: '攀岩日历',
                            color: Color(0xFFFFD85D),
                            borderColor: Color(0xFFE4A81B),
                            icon: Icons.calendar_month_rounded,
                            onTap: () => context.push('/profile/calendar'),
                          ),
                        ),
                      ],
                    ),
                    if (_weeklyRoutes.isNotEmpty || _weeklyGyms.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _HomeSectionTitle(
                        title: '本周新线',
                        trailing:
                            !widget.useWeeklyRouteMocks &&
                                _weeklyRoutes.length > 2
                            ? Text(
                                '左右滑动',
                                style: Theme.of(context).textTheme.labelMedium,
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      if (widget.useWeeklyRouteMocks)
                        WeeklyGymPreviewCarousel(
                          gyms: _weeklyGyms,
                          onOpen: _openWeeklyGym,
                        )
                      else
                        _WeeklyRoutes(
                          city: _city,
                          routes: _weeklyRoutes,
                          onOpen: _openWeeklyRoute,
                        ),
                    ],
                    const SizedBox(height: 17),
                    _HomeSectionTitle(
                      title: '附近岩馆',
                      trailing: TextButton(
                        onPressed: _showDirectory,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('查看全部'),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 19),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (_error != null && items.isEmpty)
                      WanpanErrorState(title: '岩馆列表没有加载出来', onRetry: _load)
                    else if (!_loading && items.isEmpty)
                      WanpanEmptyState(
                        title: _city == null ? '暂时还没有岩馆' : '这个城市还没有岩馆',
                        description: '切换城市或查看全部岩馆。',
                        actionLabel: '切换城市',
                        onAction: _showCityPicker,
                      )
                    else
                      for (final (index, item) in items.take(3).indexed) ...[
                        if (index > 0) const SizedBox(height: 12),
                        _DirectoryBrandCard(
                          item: item,
                          onTap: () =>
                              context.push(_brandPath(item, city: _city)),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GymDirectorySheet extends StatefulWidget {
  const _GymDirectorySheet({
    required this.repository,
    required this.initialItems,
    required this.globalItems,
    required this.cities,
    required this.initialCity,
  });

  final GymRepository repository;
  final List<GymDirectoryItem> initialItems;
  final List<GymDirectoryItem> globalItems;
  final List<String> cities;
  final String? initialCity;

  @override
  State<_GymDirectorySheet> createState() => _GymDirectorySheetState();
}

class _GymDirectorySheetState extends State<_GymDirectorySheet> {
  final _searchController = TextEditingController();
  late String? _city = widget.initialCity;
  late List<GymDirectoryItem> _items = widget.initialCity == null
      ? widget.globalItems
      : widget.initialItems;
  String _query = '';
  Object? _error;
  bool _loading = false;
  int _requestId = 0;

  List<String?> get _cityOptions => [
    if (widget.initialCity != null) widget.initialCity,
    null,
    ...widget.cities.where((city) => city != widget.initialCity),
  ];

  @override
  void dispose() {
    _requestId += 1;
    _searchController.dispose();
    super.dispose();
  }

  List<GymDirectoryItem> get _visible {
    final normalized = _query.trim().toLowerCase();
    return _items
        .where((item) {
          final matchesCity = _city == null || item.hasCity(_city!);
          final matchesQuery =
              normalized.isEmpty ||
              item.brandName.toLowerCase().contains(normalized);
          return matchesCity && matchesQuery;
        })
        .toList(growable: false);
  }

  void _chooseCity(String? city) {
    if (city == _city) return;
    _city = city;
    _error = null;
    if (city == null) {
      _requestId += 1;
      setState(() {
        _items = widget.globalItems;
        _loading = false;
      });
      return;
    }
    setState(() {
      _items = const [];
      _loading = true;
    });
    _loadCity(city);
  }

  Future<void> _loadCity(String city) async {
    final requestId = ++_requestId;
    try {
      final items = await widget.repository.getDirectory(city: city);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _retry() {
    final city = _city;
    if (city != null) {
      setState(() {
        _error = null;
        _loading = true;
      });
      _loadCity(city);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return FractionallySizedBox(
      heightFactor: .88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '找岩馆',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索岩馆或品牌',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (index, option) in _cityOptions.indexed) ...[
                  if (index > 0) const SizedBox(width: 8),
                  _CityChip(
                    label: option ?? '全部',
                    selected: _city == option,
                    onTap: () => _chooseCity(option),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const WanpanListSkeleton(itemCount: 4)
                : _error != null
                ? WanpanErrorState(title: '岩馆列表没有加载出来', onRetry: _retry)
                : visible.isEmpty
                ? const WanpanEmptyState(
                    title: '还没有找到岩馆',
                    description: '换一个城市或关键词试试。',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = visible[index];
                      return _DirectoryBrandCard(
                        item: item,
                        compact: true,
                        onTap: () => Navigator.pop(
                          context,
                          _GymDirectorySelection(item: item, city: _city),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GymDirectorySelection {
  const _GymDirectorySelection({required this.item, required this.city});

  final GymDirectoryItem item;
  final String? city;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.city,
    required this.locating,
    required this.onChooseCity,
    required this.onNotifications,
    required this.unreadCount,
  });

  final String? city;
  final bool locating;
  final VoidCallback onChooseCity;
  final VoidCallback onNotifications;
  final int unreadCount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox.square(
                  dimension: constraints.maxWidth < 350 ? 34 : 43,
                  child: const CustomPaint(painter: _CatHeadPainter()),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '完攀日记',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 25, letterSpacing: -.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .38),
            child: WanpanPressable(
              key: const Key('home-city-picker'),
              semanticLabel: '切换城市',
              onTap: onChooseCity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          locating ? '定位中' : city ?? '全国',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('home-notifications-button'),
                tooltip: unreadCount > 0 ? '消息，$unreadCount条未读' : '消息',
                onPressed: onNotifications,
                icon: const Icon(Icons.notifications_none_rounded, size: 29),
              ),
              if (unreadCount > 0)
                const Positioned(
                  key: Key('home-notifications-unread'),
                  right: 7,
                  top: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WanpanColors.coral,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 9),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.cities, required this.controller});

  final ValueNotifier<List<String>> cities;
  final HomeCityController controller;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  String _query = '';

  List<String> get _visible => <String>{
    ...widget.cities.value,
    if (widget.controller.city != null) widget.controller.city!,
  }.where((city) => city.contains(_query.trim())).toList()..sort();

  void _select(String? city) {
    unawaited(widget.controller.selectManually(city));
    Navigator.pop(context);
  }

  Future<void> _locate() async {
    await widget.controller.locate();
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        widget.controller.locationError != null) {
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _openSettings() async {
    final opened = await widget.controller.openLocationSettings();
    if (!mounted) return;
    WanpanNotice.show(
      context,
      opened ? '开启定位后，点击“使用当前位置”重试。' : '无法打开设置，请在系统设置中开启定位。',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.cities]),
    builder: (context, _) {
      final controller = widget.controller;
      final error = controller.locationError;
      final cities = _visible;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: .82,
          child: SafeArea(
            top: false,
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '选择城市',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        WanpanPressable(
                          key: const Key('use-current-location'),
                          onTap: controller.isLocating ? null : _locate,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 64),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: WanpanColors.skySoft,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: WanpanColors.sky),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.my_location_rounded,
                                  color: WanpanColors.ink,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        controller.isLocating
                                            ? '正在定位…'
                                            : '使用当前位置',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const Text('获取所在城市，查看当地岩馆'),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error.message,
                            key: const Key('city-location-error'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (error.canOpenAppSettings ||
                              error.canOpenLocationSettings)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _openSettings,
                                child: const Text('去设置'),
                              ),
                            ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('home-city-search'),
                          onChanged: (value) => setState(() => _query = value),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: '搜索城市',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CityRow(
                          key: const Key('city-option-national'),
                          label: '全国',
                          selected: controller.city == null,
                          onTap: () => _select(null),
                        ),
                        if (cities.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              _query.trim().isEmpty
                                  ? '暂无可选城市，可以定位或查看全国岩馆。'
                                  : '没有找到这个城市，换个关键词试试。',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  sliver: SliverList.builder(
                    itemCount: cities.length,
                    itemBuilder: (_, index) => _CityRow(
                      key: Key('city-option-${cities[index]}'),
                      label: cities[index],
                      selected: cities[index] == controller.city,
                      onTap: () => _select(cities[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: WanpanPressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WanpanColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: WanpanColors.coral),
          ],
        ),
      ),
    ),
  );
}

class _MonthlyProgress extends StatelessWidget {
  const _MonthlyProgress({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final sends = profile?.stats.monthlySends ?? 0;
    final maxGrade = profile?.stats.monthlyMaxGrade ?? 0;
    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      padding: const EdgeInsets.fromLTRB(17, 13, 14, 12),
      decoration: BoxDecoration(
        color: WanpanColors.surface,
        border: Border.all(color: WanpanColors.border),
        borderRadius: BorderRadius.circular(23),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      '本月成长',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.star_rounded,
                      size: 15,
                      color: WanpanColors.sunflower,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '完攀 '),
                          TextSpan(
                            text: '$sends',
                            style: const TextStyle(
                              color: WanpanColors.coral,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(text: ' 条'),
                        ],
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: WanpanColors.border),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: '最高 '),
                              TextSpan(
                                text: 'V$maxGrade',
                                style: const TextStyle(
                                  color: WanpanColors.grape,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 380 &&
              MediaQuery.textScalerOf(context).scale(14) <= 16)
            SizedBox(
              width: 92,
              height: 68,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Divider(thickness: 6, color: WanpanColors.border),
                  ),
                  Positioned(
                    right: 15,
                    top: -34,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(38),
                      child: Image.asset(
                        AppAssets.mascotWelcome,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 2,
                    bottom: 7,
                    child: _TinyHold(color: WanpanColors.coral),
                  ),
                  const Positioned(
                    left: 35,
                    bottom: 7,
                    child: _TinyHold(color: WanpanColors.grape),
                  ),
                  const Positioned(
                    right: 1,
                    bottom: 7,
                    child: _TinyHold(color: WanpanColors.sunflower),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TinyHold extends StatelessWidget {
  const _TinyHold({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 15,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: WanpanColors.catBlack, width: 1.5),
      borderRadius: const BorderRadius.all(Radius.elliptical(24, 15)),
    ),
  );
}

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      ?trailing,
      if (trailing == null)
        const Icon(
          Icons.auto_awesome_rounded,
          size: 15,
          color: WanpanColors.sunflower,
        ),
    ],
  );
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({
    required this.label,
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final Color color;
  final Color borderColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanPressable(
    onTap: onTap,
    semanticLabel: label,
    enableHaptics: true,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      height: 112,
      padding: const EdgeInsets.fromLTRB(8, 13, 8, 10),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: borderColor, offset: const Offset(0, 3))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: WanpanColors.catBlack, size: 45),
              const Positioned(
                right: -7,
                top: -5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WanpanColors.coral,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 12),
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: WanpanColors.catBlack,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WeeklyRoutes extends StatelessWidget {
  const _WeeklyRoutes({
    required this.city,
    required this.routes,
    required this.onOpen,
  });

  final String? city;
  final List<ClimbingRoute> routes;
  final ValueChanged<ClimbingRoute> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = ((constraints.maxWidth - 10) / 2).clamp(158.0, 220.0);
      return SizedBox(
        height: 126 + MediaQuery.textScalerOf(context).scale(70),
        child: ListView.separated(
          key: ValueKey('weekly-routes-${city ?? 'national'}'),
          scrollDirection: Axis.horizontal,
          itemCount: routes.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, index) => SizedBox(
            width: width,
            child: _WeeklyRouteCard(
              key: Key('weekly-route-${routes[index].id}'),
              route: routes[index],
              onTap: () => onOpen(routes[index]),
            ),
          ),
        ),
      );
    },
  );
}

class _WeeklyRouteCard extends StatelessWidget {
  const _WeeklyRouteCard({required this.route, required this.onTap, super.key});

  final ClimbingRoute route;
  final VoidCallback onTap;

  String get _dateLabel {
    final date = route.createdAt?.toUtc().add(const Duration(hours: 8));
    return date == null ? '本周新增' : '${date.month}/${date.day} 新增';
  }

  String get _gymLabel => [
    route.gymCity,
    route.gymName,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: WanpanColors.skySoft,
      child: Center(
        child: Icon(Icons.route_rounded, color: WanpanColors.sky, size: 32),
      ),
    );
    final cover = route.coverUrl;
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: '查看${route.name}，${route.grade}，$_gymLabel',
      borderRadius: BorderRadius.circular(20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          border: Border.all(color: WanpanColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 80,
              child: cover == null || cover.isEmpty
                  ? fallback
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                      excludeFromSemantics: true,
                      loadingBuilder: (_, child, loading) =>
                          loading == null ? child : fallback,
                      errorBuilder: (_, _, _) => fallback,
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _gymLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: WanpanColors.grapeSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            route.grade,
                            style: const TextStyle(
                              color: WanpanColors.grape,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryBrandCard extends StatelessWidget {
  const _DirectoryBrandCard({
    required this.item,
    required this.onTap,
    this.compact = false,
  });
  final GymDirectoryItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => WanpanPressable(
    onTap: onTap,
    semanticLabel: '打开${item.brandName}',
    borderRadius: BorderRadius.circular(22),
    child: Container(
      constraints: BoxConstraints(minHeight: compact ? 78 : 94),
      padding: EdgeInsets.all(compact ? 12 : 13),
      decoration: BoxDecoration(
        color: WanpanColors.surface,
        border: Border.all(color: WanpanColors.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _BrandMark(item: item, size: compact ? 54 : 68),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: Color(0xFF3D9FE8),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.areaLabel} · ${item.storeCount} 家门店 · ${item.routeCount} 条线路',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: WanpanColors.ink,
            size: 27,
          ),
        ],
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.item, required this.size});
  final GymDirectoryItem item;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: WanpanColors.skySoft,
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: item.logoUrl == null
        ? Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.cottage_rounded,
                color: WanpanColors.ink,
                size: 34,
              ),
              const Positioned(
                bottom: 7,
                child: Row(
                  children: [
                    _TinyDot(color: WanpanColors.coral),
                    SizedBox(width: 3),
                    _TinyDot(color: WanpanColors.sunflower),
                    SizedBox(width: 3),
                    _TinyDot(color: WanpanColors.grape),
                  ],
                ),
              ),
            ],
          )
        : Image.network(
            item.logoUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
            cacheHeight: (size * 3).round(),
            errorBuilder: (_, _, _) =>
                const Icon(Icons.cottage_rounded, color: WanpanColors.coral),
          ),
  );
}

class _TinyDot extends StatelessWidget {
  const _TinyDot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: const SizedBox.square(dimension: 5),
  );
}

class _CityChip extends StatelessWidget {
  const _CityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

class _CatHeadPainter extends CustomPainter {
  const _CatHeadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final black = Paint()..color = WanpanColors.catBlack;
    final white = Paint()..color = Colors.white;
    final head = Path()
      ..moveTo(size.width * .12, size.height * .30)
      ..lineTo(size.width * .19, size.height * .05)
      ..lineTo(size.width * .38, size.height * .20)
      ..quadraticBezierTo(
        size.width * .50,
        size.height * .15,
        size.width * .63,
        size.height * .20,
      )
      ..lineTo(size.width * .83, size.height * .05)
      ..lineTo(size.width * .88, size.height * .33)
      ..quadraticBezierTo(
        size.width * .94,
        size.height * .78,
        size.width * .50,
        size.height * .91,
      )
      ..quadraticBezierTo(
        size.width * .06,
        size.height * .78,
        size.width * .12,
        size.height * .30,
      )
      ..close();
    canvas.drawPath(head, black);
    canvas.drawCircle(Offset(size.width * .35, size.height * .50), 7, white);
    canvas.drawCircle(Offset(size.width * .66, size.height * .50), 7, white);
    canvas.drawCircle(Offset(size.width * .35, size.height * .50), 3, black);
    canvas.drawCircle(Offset(size.width * .66, size.height * .50), 3, black);
    final whisker = Paint()
      ..color = WanpanColors.catBlack
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (.55 + i * .08);
      canvas.drawLine(Offset(1, y), Offset(size.width * .16, y - 1), whisker);
      canvas.drawLine(
        Offset(size.width * .84, y - 1),
        Offset(size.width - 1, y),
        whisker,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
