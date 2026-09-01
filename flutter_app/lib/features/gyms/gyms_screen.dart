import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/gym_repository.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';
import '../auth/application/session_controller.dart';

class GymsScreen extends StatefulWidget {
  const GymsScreen({required this.api, required this.session, super.key});

  final ApiClient api;
  final SessionController session;

  @override
  State<GymsScreen> createState() => _GymsScreenState();
}

class _GymsScreenState extends State<GymsScreen> {
  late final GymRepository _repository = GymRepository(widget.api);
  late final ProfileRepository _profileRepository = ProfileRepository(
    widget.api,
  );
  List<GymDirectoryItem> _items = const [];
  UserProfile? _profile;
  String? _city;
  Object? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final profileFuture = _tryLoadProfile();
    try {
      final items = await _repository.getDirectory();
      final profile = await profileFuture;
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = items;
        _profile = profile;
        _city ??= items.isEmpty ? null : items.first.city;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error);
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Set<String> get _cities => _items.map((item) => item.city).toSet();

  List<GymDirectoryItem> get _cityItems => _city == null
      ? _items
      : _items.where((item) => item.city == _city).toList(growable: false);

  Future<void> _showDirectory() async {
    final selected = await showModalBottomSheet<GymDirectoryItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GymDirectorySheet(
        items: _items,
        cities: _cities,
        initialCity: _city,
      ),
    );
    if (selected != null && mounted) {
      await context.push('/brands/${selected.brandId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _cityItems;
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
                      cities: _cities,
                      onCityChanged: (value) => setState(() => _city = value),
                      onUpdates: () => context.go('/feed'),
                    ),
                    const SizedBox(height: 14),
                    _HomeHero(
                      onFindRoute: () => context.push('/routes/pick'),
                      onBrowseGyms: _showDirectory,
                    ),
                    const SizedBox(height: 10),
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
                            onTap: () => context.push('/route-submissions/new'),
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
                    const SizedBox(height: 16),
                    const _HomeSectionTitle(title: '本周新线'),
                    const SizedBox(height: 8),
                    if (_loading && items.isEmpty)
                      const SizedBox(
                        height: 86,
                        child: WanpanListSkeleton(itemCount: 1),
                      )
                    else if (items.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: _WeeklyCard(
                              item: items.first,
                              color: WanpanColors.skySoft,
                              accent: WanpanColors.sky,
                              mascot: AppAssets.mascotCelebrate,
                              onTap: () => context.push(
                                '/brands/${items.first.brandId}',
                              ),
                            ),
                          ),
                          if (items.length > 1) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _WeeklyCard(
                                item: items[1],
                                color: WanpanColors.grapeSoft,
                                accent: WanpanColors.grape,
                                mascot: AppAssets.mascotWelcome,
                                onTap: () =>
                                    context.push('/brands/${items[1].brandId}'),
                              ),
                            ),
                          ],
                        ],
                      ),
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
                        title: '这个城市还没有岩馆',
                        description: '切换城市或查看全部岩馆。',
                        actionLabel: '查看全部',
                        onAction: _showDirectory,
                      )
                    else if (items.isNotEmpty)
                      _DirectoryBrandCard(
                        item: items.first,
                        onTap: () =>
                            context.push('/brands/${items.first.brandId}'),
                      ),
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
    required this.items,
    required this.cities,
    required this.initialCity,
  });

  final List<GymDirectoryItem> items;
  final Set<String> cities;
  final String? initialCity;

  @override
  State<_GymDirectorySheet> createState() => _GymDirectorySheetState();
}

class _GymDirectorySheetState extends State<_GymDirectorySheet> {
  final _searchController = TextEditingController();
  late String? _city = widget.initialCity;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GymDirectoryItem> get _visible {
    final normalized = _query.trim().toLowerCase();
    return widget.items
        .where((item) {
          final matchesCity = _city == null || item.city == _city;
          final matchesQuery =
              normalized.isEmpty ||
              item.brandName.toLowerCase().contains(normalized);
          return matchesCity && matchesQuery;
        })
        .toList(growable: false);
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
                _CityChip(
                  label: '全部',
                  selected: _city == null,
                  onTap: () => setState(() => _city = null),
                ),
                for (final option in widget.cities) ...[
                  const SizedBox(width: 8),
                  _CityChip(
                    label: option,
                    selected: _city == option,
                    onTap: () => setState(() => _city = option),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
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
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.city,
    required this.cities,
    required this.onCityChanged,
    required this.onUpdates,
  });

  final String? city;
  final Set<String> cities;
  final ValueChanged<String?> onCityChanged;
  final VoidCallback onUpdates;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 43,
          child: CustomPaint(painter: _CatHeadPainter()),
        ),
        const SizedBox(width: 7),
        Text(
          '完攀日记',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 25, letterSpacing: -.8),
        ),
        const Spacer(),
        PopupMenuButton<String?>(
          tooltip: '切换城市',
          onSelected: onCityChanged,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: null, child: Text('全部城市')),
            for (final option in cities)
              PopupMenuItem(value: option, child: Text(option)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Text(
                  city ?? '全国',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 2),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
              ],
            ),
          ),
        ),
        const SizedBox(width: 2),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: '看看新动态',
              onPressed: onUpdates,
              icon: const Icon(Icons.notifications_none_rounded, size: 29),
            ),
            const Positioned(
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
  );
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.onFindRoute, required this.onBrowseGyms});
  final VoidCallback onFindRoute;
  final VoidCallback onBrowseGyms;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 355;
      return Container(
        height: compact ? 270 : 286,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9EA),
          border: Border.all(color: WanpanColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(27),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _HeroPathPainter()),
            ),
            Positioned(
              right: compact ? -24 : -18,
              top: 43,
              width: compact ? 206 : 224,
              height: 232,
              child: Image.asset(
                AppAssets.homeHeroCat,
                fit: BoxFit.contain,
                cacheWidth: 560,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => Image.asset(
                  AppAssets.mascotCelebrate,
                  fit: BoxFit.contain,
                  cacheWidth: 560,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            Positioned(
              right: 11,
              top: 17,
              child: Transform.rotate(
                angle: -.05,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: WanpanColors.surface,
                    border: Border.all(color: WanpanColors.catBlack, width: 2),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Text(
                    '出发喵！',
                    style: TextStyle(
                      color: WanpanColors.catBlack,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 20,
              width: compact ? 174 : 190,
              child: Text(
                '今天也去\n上墙吧！',
                style: TextStyle(
                  color: WanpanColors.catBlack,
                  fontSize: compact ? 31 : 35,
                  height: 1.05,
                  letterSpacing: -1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Positioned(
              left: 21,
              top: compact ? 101 : 107,
              width: compact ? 168 : 184,
              child: const Text(
                '找条喜欢的线路，\n记录一次新完攀',
                style: TextStyle(
                  color: WanpanColors.ink,
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 52,
              width: compact ? 169 : 181,
              child: _CoralAction(label: '找线路打卡', onTap: onFindRoute),
            ),
            Positioned(
              left: 24,
              bottom: 14,
              child: WanpanPressable(
                onTap: onBrowseGyms,
                semanticLabel: '先看看岩馆',
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '先看看岩馆',
                        style: TextStyle(
                          color: WanpanColors.ink,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.underline,
                          decorationThickness: 1.5,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CoralAction extends StatelessWidget {
  const _CoralAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: WanpanPressable(
      onTap: onTap,
      semanticLabel: label,
      enableHaptics: true,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: WanpanColors.coral,
          border: Border.all(color: WanpanColors.catBlack, width: 2),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: WanpanColors.catBlack,
              offset: Offset(0, 5),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: .2,
          ),
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
      height: 94,
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
                Row(
                  children: [
                    const Text(
                      '完攀 ',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '$sends',
                      style: const TextStyle(
                        color: WanpanColors.coral,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      ' 条',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 25, color: WanpanColors.border),
                    const SizedBox(width: 12),
                    const Text(
                      '最高 ',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'V$maxGrade',
                      style: const TextStyle(
                        color: WanpanColors.grape,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
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

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({
    required this.item,
    required this.color,
    required this.accent,
    required this.mascot,
    required this.onTap,
  });
  final GymDirectoryItem item;
  final Color color;
  final Color accent;
  final String mascot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanPressable(
    onTap: onTap,
    semanticLabel: '打开${item.brandName}',
    borderRadius: BorderRadius.circular(19),
    child: Container(
      height: 85,
      padding: const EdgeInsets.fromLTRB(12, 10, 72, 10),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: accent.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(19),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.brandName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WanpanColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${item.routeCount} 条线路',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: -79,
            bottom: -45,
            child: ClipOval(
              child: Image.asset(
                mascot,
                width: 126,
                height: 126,
                fit: BoxFit.cover,
                cacheWidth: 250,
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
                  '${item.city} · ${item.storeCount} 家门店 · ${item.routeCount} 条线路',
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

class _HeroPathPainter extends CustomPainter {
  const _HeroPathPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEADFCB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(size.width * .62, 0)
      ..cubicTo(
        size.width * .46,
        size.height * .26,
        size.width * .60,
        size.height * .50,
        size.width * .44,
        size.height,
      );
    canvas.drawPath(path, paint);
    final dot = Paint()..color = const Color(0xFFEADFCB);
    for (final point in <Offset>[
      Offset(size.width * .68, 28),
      Offset(size.width * .82, 23),
      Offset(size.width * .94, 38),
      Offset(size.width * .48, size.height * .88),
      Offset(size.width * .59, size.height * .79),
    ]) {
      canvas.drawCircle(point, 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
