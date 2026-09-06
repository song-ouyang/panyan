import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/growth_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/growth_repository.dart';
import '../../shared/widgets/wanpan_account_badge.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../auth/application/session_controller.dart';
import 'badge_celebration.dart';

class GrowthScreen extends StatefulWidget {
  const GrowthScreen({required this.api, required this.session, super.key});
  final ApiClient api;
  final SessionController session;
  @override
  State<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends State<GrowthScreen> {
  late final _repository = GrowthRepository.forSession(
    widget.api,
    widget.session,
  );
  bool _loading = true;
  String? _error;
  int _request = 0;
  bool _historyAttempted = false;
  bool _presenting = false;
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    _repository.addListener(_changed);
    widget.api.climbingActivity.addListener(_reload);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkHistoryPresentation());
      });
    }
  }

  Future<void> _checkHistoryPresentation() async {
    // Profile only shows the compact Lv. indicator. Historical awards are
    // presented after the user explicitly enters this detail destination.
    if (_historyAttempted ||
        _presenting ||
        !_visible ||
        _repository.snapshot == null ||
        !widget.session.isAuthenticated ||
        (GoRouter.maybeOf(context)?.state.uri.path != null &&
            GoRouter.maybeOf(context)?.state.uri.path != '/profile/badges')) {
      return;
    }
    _presenting = true;
    final generation = _repository.sessionGeneration;
    try {
      final presentation = await _repository.consumePresentation();
      if (!mounted || !_repository.isCurrentSession(generation)) return;
      _historyAttempted = true;
      if (_repository.badges.isEmpty) await _repository.loadBadges();
      if (!mounted ||
          !_visible ||
          !_repository.isCurrentSession(generation) ||
          presentation == null) {
        return;
      }
      await showBadgeCelebration(
        context,
        repository: _repository,
        presentation: presentation,
      );
    } catch (_) {
      if (mounted && _repository.isCurrentSession(generation)) {
        setState(() => _error = '徽章已保存，展示同步失败，点此重试');
      }
    } finally {
      _presenting = false;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _reload() => unawaited(_load());
  Future<void> _load() async {
    final request = ++_request;
    final generation = _repository.sessionGeneration;
    if (!widget.session.isAuthenticated) return;
    setState(() {
      _loading = _repository.snapshot == null;
      _error = null;
    });
    try {
      await _repository.loadBadges();
      if (mounted &&
          request == _request &&
          _repository.isCurrentSession(generation)) {
        unawaited(_checkHistoryPresentation());
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          _repository.isCurrentSession(generation)) {
        setState(() => _error = '徽章暂时没有加载出来，点此重试');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _repository.removeListener(_changed);
    widget.api.climbingActivity.removeListener(_reload);
    super.dispose();
  }

  Future<void> _detail(UserBadge badge) async {
    final generation = _repository.sessionGeneration;
    Route<void>? detailsRoute;
    NavigatorState? detailsNavigator;
    void invalidateDetails() {
      final invalidBadge =
          badge.status == UserBadgeStatus.earned &&
          ((_repository.snapshot?.currentLevel ?? 0) < badge.level ||
              !_repository.badges.any(
                (current) =>
                    current.badgeKey == badge.badgeKey &&
                    current.status == UserBadgeStatus.earned,
              ));
      if ((!_repository.isCurrentSession(generation) || invalidBadge) &&
          detailsRoute?.isActive == true) {
        detailsNavigator?.removeRoute(detailsRoute!);
      }
    }

    widget.session.addListener(invalidateDetails);
    _repository.addListener(invalidateDetails);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          detailsRoute = ModalRoute.of<void>(sheetContext);
          detailsNavigator = Navigator.of(sheetContext);
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WanpanAccountBadge(
                      level: badge.level,
                      size: 200,
                      dimmed: badge.status != UserBadgeStatus.earned,
                    ),
                    Text(
                      'Lv.${badge.level} · ${badge.name}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(badge.statusLabel),
                    const SizedBox(height: 12),
                    Text(
                      '累计 ${badge.days} 个攀爬日，并完攀 ${badge.routes} 条不同线路',
                      textAlign: TextAlign.center,
                    ),
                    if (badge.earnedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('首次获得：${_date(badge.earnedAt!)}'),
                      ),
                    if (badge.status == UserBadgeStatus.revoked)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          '相关完攀记录已撤销。再次满足条件时，会恢复这枚徽章。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (badge.status == UserBadgeStatus.earned)
                      WanpanButton(
                        label: '重播获得动效',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!_repository.isCurrentSession(generation) ||
                              (_repository.snapshot?.currentLevel ?? 0) <
                                  badge.level ||
                              !_repository.badges.any(
                                (current) =>
                                    current.badgeKey == badge.badgeKey &&
                                    current.status == UserBadgeStatus.earned,
                              )) {
                            return;
                          }
                          // Replay is purely visual and never consumes or awards a server event.
                          unawaited(
                            showBadgeCelebration(
                              context,
                              repository: _repository,
                              presentation: GrowthPresentation(
                                id: 'replay:${badge.badgeKey}',
                                fromLevel: badge.level,
                                toLevel: badge.level,
                                badgeKeys: [badge.badgeKey],
                                newBadgeCount: 1,
                                levelName: badge.name,
                                growthRevision:
                                    _repository.snapshot?.revision ?? 0,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('知道了'),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      widget.session.removeListener(invalidateDetails);
      _repository.removeListener(invalidateDetails);
    }
  }

  String _date(DateTime date) {
    final value = date.toUtc().add(const Duration(hours: 8));
    return '${value.year}年${value.month}月${value.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final growth = _repository.snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('等级与徽章')),
      body: !widget.session.isAuthenticated
          ? const Center(child: Text('请登录后查看徽章'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    TextButton(onPressed: _load, child: Text(_error!)),
                  if (growth != null) ...[
                    WanpanCard(
                      child: Column(
                        children: [
                          WanpanAccountBadge(
                            level: growth.currentLevel,
                            size: 164,
                          ),
                          Text(
                            'Lv.${growth.currentLevel} · ${growth.levelName}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text('记录攀爬，收藏每一份热爱。'),
                          const SizedBox(height: 22),
                          GrowthProgress(snapshot: growth),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text('我的徽章', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560 ? 4 : 2;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 12) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _repository.badges
                            .map(
                              (badge) => SizedBox(
                                width: width,
                                child: WanpanPressable(
                                  semanticLabel:
                                      'Lv.${badge.level} ${badge.name}，${badge.statusLabel}，查看详情',
                                  onTap: () => _detail(badge),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: WanpanColors.surface,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: WanpanColors.border,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        WanpanAccountBadge(
                                          level: badge.level,
                                          size: (width - 24).clamp(64, 140),
                                          dimmed:
                                              badge.status !=
                                              UserBadgeStatus.earned,
                                        ),
                                        Text(
                                          'Lv.${badge.level} ${badge.name}',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          badge.statusLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '成长规则',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '北京时间同一天有有效完攀记 1 个攀爬日；同一条线路累计只记 1 条。两项都达到门槛才会升级，休息不会扣减。账户 Lv 等级与线路 V 难度分别计算。',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '历史等级根据仍保留的完攀记录计算；删除完攀记录会更新进度及对应徽章。',
                    style: TextStyle(color: WanpanColors.inkSecondary),
                  ),
                ],
              ),
            ),
    );
  }
}

class GrowthProgress extends StatelessWidget {
  const GrowthProgress({required this.snapshot, super.key});
  final GrowthSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final next = snapshot.nextLevel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          next == null ? '当前最高等级' : '下一站 Lv.${next.level} · ${next.name}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _ProgressLine(
          label: '累计攀爬日',
          value: next == null
              ? '${snapshot.climbingDays} 天'
              : '${snapshot.climbingDays} / ${next.days} 天',
          progress: snapshot.daysProgress,
          color: WanpanColors.coral,
        ),
        const SizedBox(height: 14),
        _ProgressLine(
          label: '不同完攀线路',
          value: next == null
              ? '${snapshot.uniqueRoutes} 条'
              : '${snapshot.uniqueRoutes} / ${next.routes} 条',
          progress: snapshot.routesProgress,
          color: WanpanColors.grape,
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              '还需 ${snapshot.remainingDays} 个攀爬日、${snapshot.remainingRoutes} 条线路',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (snapshot.backfillStatus != 'complete')
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('正在整理历史完攀记录，进度会自动更新。'),
          ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });
  final String label;
  final String value;
  final double progress;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label，$value',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 7),
        ExcludeSemantics(
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: color,
            backgroundColor: WanpanColors.surfaceSoft,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ],
    ),
  );
}
