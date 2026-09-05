import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/gym_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/preferences/gym_selection_store.dart';
import '../../core/repositories/gym_repository.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_gym_picker.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';
import '../auth/application/session_controller.dart';

class RoutePickerScreen extends StatefulWidget {
  const RoutePickerScreen({
    required this.api,
    required this.session,
    super.key,
    this.initialGymId,
    this.gymRepository,
    this.selectionStore,
  });

  final ApiClient api;
  final SessionController session;
  final String? initialGymId;
  final GymRepository? gymRepository;
  final GymSelectionStore? selectionStore;

  @override
  State<RoutePickerScreen> createState() => _RoutePickerScreenState();
}

class _RoutePickerScreenState extends State<RoutePickerScreen> {
  late final GymRepository _repository;
  final _searchController = TextEditingController();

  List<Gym> _gyms = const [];
  GymDetail? _gymDetail;
  List<ClimbingRoute> _routes = const [];
  String? _gymId;
  String? _grade;
  String? _routeSetId;
  String _query = '';
  Object? _gymsError;
  Object? _routesError;
  bool _loadingGyms = true;
  bool _loadingRoutes = false;
  int _requestId = 0;
  GymSelectionStore? _selectionStore;
  bool _restoringSelection = true;

  @override
  void initState() {
    super.initState();
    _repository = widget.gymRepository ?? GymRepository(widget.api);
    _restoreSelection();
    _loadGyms();
  }

  Future<void> _restoreSelection() async {
    final requestId = _requestId;
    try {
      _selectionStore = widget.selectionStore ?? await GymSelectionStore.load();
    } catch (_) {
      // A local preference failure must not prevent choosing a gym.
    }
    if (!mounted || requestId != _requestId) return;
    setState(() => _restoringSelection = false);
    final initialGymId = widget.initialGymId?.trim();
    final hasExplicitGym = initialGymId != null && initialGymId.isNotEmpty;
    final gymId = hasExplicitGym ? initialGymId : _selectionStore?.gymId;
    if (gymId != null) {
      await _selectGym(gymId, rememberSelection: hasExplicitGym);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClimbingRoute> get _visibleRoutes {
    final query = _query.trim().toLowerCase();
    return _routes
        .where((route) {
          if (_grade != null && route.grade != _grade) return false;
          if (_routeSetId != null && route.routeSetId != _routeSetId) {
            return false;
          }
          if (query.isEmpty) return true;
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

  Gym? get _selectedGym {
    final detailGym = _gymDetail?.gym;
    if (detailGym != null) return detailGym;
    return _gyms.where((gym) => gym.id == _gymId).firstOrNull;
  }

  Future<void> _loadGyms() async {
    setState(() {
      _loadingGyms = true;
      _gymsError = null;
    });
    try {
      final gyms = await _repository.getGyms();
      if (!mounted) return;
      setState(() => _gyms = gyms);
    } catch (error) {
      if (mounted) setState(() => _gymsError = error);
    } finally {
      if (mounted) setState(() => _loadingGyms = false);
    }
  }

  Future<void> _loadGym(
    String gymId, {
    bool resetFilters = true,
    bool rememberSelection = false,
  }) async {
    final requestId = ++_requestId;
    final previousSavedGymId = _selectionStore?.gymId;
    var missingGym = false;
    setState(() {
      _loadingRoutes = true;
      _routesError = null;
      if (resetFilters) {
        _query = '';
        _grade = null;
        _routeSetId = null;
        _searchController.clear();
      }
    });
    try {
      final results = await Future.wait<Object>([
        _repository.getGym(gymId).onError<Object>((error, stackTrace) {
          missingGym = error is ApiException && error.statusCode == 404;
          Error.throwWithStackTrace(error, stackTrace);
        }),
        _repository.getRoutes(gymId),
      ]);
      if (!mounted || requestId != _requestId || _gymId != gymId) return;
      final detail = results[0] as GymDetail;
      final activeSet = detail.routeSets.where((set) => set.active).firstOrNull;
      setState(() {
        _gymDetail = detail;
        _routes = results[1] as List<ClimbingRoute>;
        if (resetFilters) _routeSetId = activeSet?.id;
      });
      if (rememberSelection &&
          ModalRoute.of(context)?.isCurrent == true &&
          _selectionStore?.gymId == previousSavedGymId) {
        try {
          await _selectionStore?.rememberGym(detail.gym);
        } catch (_) {
          // Keep a usable selection even when preferences cannot be written.
        }
      }
    } catch (error) {
      if (!mounted || requestId != _requestId || _gymId != gymId) return;
      if (missingGym) {
        setState(() {
          _gymId = null;
          _gymDetail = null;
          _routes = const [];
          _loadingRoutes = false;
        });
        if (_selectionStore?.gymId == gymId) {
          try {
            await _selectionStore?.clearGym();
          } catch (_) {
            // The missing gym is still cleared from this screen.
          }
        }
      } else {
        setState(() => _routesError = error);
      }
    } finally {
      if (mounted && requestId == _requestId && _gymId == gymId) {
        setState(() => _loadingRoutes = false);
      }
    }
  }

  Future<void> _selectGym(
    String gymId, {
    bool rememberSelection = false,
  }) async {
    if (_gymId == gymId && _gymDetail != null) return;
    setState(() {
      _gymId = gymId;
      _gymDetail = null;
      _routes = const [];
      _restoringSelection = false;
    });
    await _loadGym(gymId, rememberSelection: rememberSelection);
  }

  Future<void> _openGymPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_gyms.isEmpty && !_loadingGyms) await _loadGyms();
    if (!mounted) return;
    if (_gyms.isEmpty) {
      _notice(_gymsError == null ? '正在读取岩馆…' : '岩馆列表没有加载出来');
      return;
    }
    final gymId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WanpanGymPickerSheet(
        gyms: _gyms,
        selectedGymId: _gymId,
        selectionStore: _selectionStore ?? widget.selectionStore,
      ),
    );
    if (gymId != null && mounted) await _selectGym(gymId);
  }

  Future<void> _checkin(ClimbingRoute route) async {
    final completed = await context.push<bool>(
      '/routes/${route.id}/checkin',
      extra: <String, String>{'name': route.name, 'grade': route.grade},
    );
    if (completed == true && mounted && _gymId != null) {
      await _loadGym(_gymId!, resetFilters: false);
    }
  }

  Future<void> _openRoute(ClimbingRoute route) async {
    await context.push('/routes/${route.id}');
  }

  Future<void> _publishRoute() async {
    final gymId = _gymId;
    final location = gymId == null
        ? '/route-submissions/new'
        : '/route-submissions/new?gymId=${Uri.encodeQueryComponent(gymId)}';
    final created = await context.push<bool>(location);
    if (created == true && mounted && _gymId != null) {
      await _loadGym(_gymId!, resetFilters: false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('找线路打卡')),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WanpanSpacing.page,
              WanpanSpacing.sm,
              WanpanSpacing.page,
              WanpanSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GymField(
                  gym: _selectedGym,
                  loading:
                      (_loadingGyms || _restoringSelection || _loadingRoutes) &&
                      _selectedGym == null,
                  onTap: _openGymPicker,
                ),
                if (_gymId != null) ...[
                  const SizedBox(height: WanpanSpacing.sm),
                  TextField(
                    controller: _searchController,
                    enabled: !_loadingRoutes,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: '线路名、颜色或墙区',
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
                  _FilterRow(
                    routeSets: _gymDetail?.routeSets ?? const [],
                    grade: _grade,
                    routeSetId: _routeSetId,
                    onGradeChanged: (value) => setState(() => _grade = value),
                    onRouteSetChanged: (value) =>
                        setState(() => _routeSetId = value),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() {
    if (_gymId == null) {
      return WanpanEmptyState(
        title: '先选一家岩馆',
        description: '选好门店后，可以按难度、线路周期和关键词快速找线。',
        actionLabel: '选择岩馆',
        onAction: _openGymPicker,
        imageAsset: null,
      );
    }
    if (_loadingRoutes && _routes.isEmpty) {
      return const WanpanListSkeleton(itemCount: 4);
    }
    if (_routesError != null && _routes.isEmpty) {
      return WanpanErrorState(
        title: '线路没有加载出来',
        onRetry: () => _loadGym(_gymId!, resetFilters: false),
      );
    }

    final visibleRoutes = _visibleRoutes;
    if (visibleRoutes.isEmpty) {
      return WanpanEmptyState(
        title: '没找到这条线路',
        description: '试试改难度、周期或关键词；如果是新线，可以直接发布。',
        actionLabel: '发布新线路',
        onAction: _publishRoute,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadGym(_gymId!, resetFilters: false),
      color: WanpanColors.coral,
      child: ListView.separated(
        key: PageStorageKey('route-picker-${_gymId!}'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          WanpanSpacing.page,
          4,
          WanpanSpacing.page,
          WanpanSpacing.xl,
        ),
        itemCount: visibleRoutes.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Text(
                    '找到 ${visibleRoutes.length} 条',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    '点击线路直接打卡',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            );
          }
          if (index == visibleRoutes.length + 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: WanpanButton(
                label: '没找到？发布新线路',
                style: WanpanButtonStyle.quiet,
                icon: const Icon(Icons.add_rounded),
                onPressed: _publishRoute,
              ),
            );
          }
          final route = visibleRoutes[index - 1];
          return _RouteChoiceCard(
            route: route,
            onTap: () => _checkin(route),
            onOpenDetail: () => _openRoute(route),
          );
        },
      ),
    );
  }
}

class _GymField extends StatelessWidget {
  const _GymField({
    required this.gym,
    required this.loading,
    required this.onTap,
  });

  final Gym? gym;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    semanticLabel: gym == null ? '选择岩馆' : '更换岩馆，当前${gym!.name}',
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WanpanColors.coralSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(
                  Icons.location_on_rounded,
                  color: WanpanColors.coralStrong,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                gym?.name ?? '选择岩馆',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                gym == null
                    ? '先确认你在哪家门店'
                    : [
                        gym!.city,
                        ?gym!.displayDistrict,
                        gym!.address,
                      ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const Icon(Icons.unfold_more_rounded, color: WanpanColors.muted),
      ],
    ),
  );
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.routeSets,
    required this.grade,
    required this.routeSetId,
    required this.onGradeChanged,
    required this.onRouteSetChanged,
  });

  final List<RouteSet> routeSets;
  final String? grade;
  final String? routeSetId;
  final ValueChanged<String?> onGradeChanged;
  final ValueChanged<String?> onRouteSetChanged;

  @override
  Widget build(BuildContext context) {
    final routeSetName = routeSets
        .where((set) => set.id == routeSetId)
        .firstOrNull
        ?.name;
    return Row(
      children: [
        Expanded(
          child: _PopupFilter(
            label: grade ?? '全部难度',
            semanticLabel: '按难度筛选',
            items: <_FilterValue>[
              const _FilterValue(value: '', label: '全部难度'),
              for (var level = 0; level <= 17; level++)
                _FilterValue(value: 'V$level', label: 'V$level'),
            ],
            onSelected: (value) => onGradeChanged(value.isEmpty ? null : value),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PopupFilter(
            label: routeSetName ?? '全部周期',
            semanticLabel: '按线路周期筛选',
            items: <_FilterValue>[
              const _FilterValue(value: '', label: '全部周期'),
              ...routeSets.map(
                (set) => _FilterValue(
                  value: set.id,
                  label: '${set.name}${set.active ? ' · 当前' : ''}',
                ),
              ),
            ],
            onSelected: (value) =>
                onRouteSetChanged(value.isEmpty ? null : value),
          ),
        ),
      ],
    );
  }
}

class _FilterValue {
  const _FilterValue({required this.value, required this.label});

  final String value;
  final String label;
}

class _PopupFilter extends StatelessWidget {
  const _PopupFilter({
    required this.label,
    required this.semanticLabel,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final String semanticLabel;
  final List<_FilterValue> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: semanticLabel,
    onSelected: onSelected,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    itemBuilder: (_) => items
        .map(
          (item) =>
              PopupMenuItem<String>(value: item.value, child: Text(item.label)),
        )
        .toList(growable: false),
    child: Semantics(
      button: true,
      label: semanticLabel,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: WanpanColors.surfaceSoft,
          border: Border.all(color: WanpanColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 19),
          ],
        ),
      ),
    ),
  );
}

class _RouteChoiceCard extends StatelessWidget {
  const _RouteChoiceCard({
    required this.route,
    required this.onTap,
    required this.onOpenDetail,
  });

  final ClimbingRoute route;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    semanticLabel: '选择${route.name}并直接打卡',
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox.square(
            dimension: 64,
            child: route.coverUrl?.trim().isNotEmpty != true
                ? ColoredBox(
                    color: WanpanColors.coralSoft,
                    child: Center(
                      child: Text(
                        route.grade,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: WanpanColors.coralStrong),
                      ),
                    ),
                  )
                : Image.network(
                    route.coverUrl!.trim(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: WanpanColors.coralSoft,
                      child: Icon(
                        Icons.landscape_rounded,
                        color: WanpanColors.coral,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: WanpanColors.coralSoft,
                      borderRadius: BorderRadius.circular(WanpanRadii.pill),
                    ),
                    child: Text(
                      route.grade,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: WanpanColors.coralStrong),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                <String>[
                  route.color,
                  if (route.wallZone != null) route.wallZone!,
                  if (route.routeSetName != null) route.routeSetName!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 5),
              Text(
                '点击直接上传视频与配文',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: WanpanColors.coralStrong),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: '查看线路详情',
          onPressed: onOpenDetail,
          icon: const Icon(Icons.info_outline_rounded),
          color: WanpanColors.muted,
        ),
      ],
    ),
  );
}
