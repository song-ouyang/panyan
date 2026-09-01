import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/json/json_helpers.dart';
import '../../core/models/ranking_models.dart';
import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_pressable.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, required this.api, required this.session});
  final ApiClient api;
  final SessionController session;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  int _segment = 0;
  bool _loading = true;
  String? _error;
  RankingBoard? _board;
  List<RankedRoute> _routes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_segment == 0) {
        if (!widget.session.isAuthenticated) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        _board = RankingBoard.fromJson(
          await widget.api.getJson(
            '/rankings',
            queryParameters: {'scope': 'national'},
          ),
        );
      } else {
        final data = await widget.api.getJson('/rankings/routes');
        _routes = jsonModelList(data['items'], RankedRoute.fromJson);
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '榜单正在整理中';
      });
    }
  }

  void _changeSegment(int value) {
    if (_segment == value) return;
    setState(() => _segment = value);
    _load();
  }

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
              onChanged: _changeSegment,
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
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(strokeWidth: 3),
      );
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
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );
    }
    if (_segment == 0 && !widget.session.isAuthenticated) {
      return const _RankingEmpty(
        key: ValueKey('signed-out'),
        title: '登录后加入全国榜',
        description: '每次完攀、首攀和收到点赞都会增加积分。',
      );
    }
    if (_segment == 0) return _people();
    return _popularRoutes();
  }

  Widget _people() {
    final board = _board;
    if (board == null || board.items.isEmpty) {
      return const _RankingEmpty(
        key: ValueKey('people-empty'),
        title: '本月榜单刚刚开始',
        description: '完成一条线路，就能出现在这里。',
      );
    }
    return RefreshIndicator(
      key: const ValueKey('people'),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _ScoringCard(board: board),
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
      return const _RankingEmpty(
        key: ValueKey('routes-empty'),
        title: '还没有热门线路',
        description: '路线有完攀和点赞后会进入榜单。',
      );
    }
    return RefreshIndicator(
      key: const ValueKey('routes'),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) =>
            _RouteTile(rank: index + 1, route: _routes[index]),
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.value, required this.onChanged});
  final int value;
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
        children: [_segment(context, 0, '全国榜'), _segment(context, 1, '热门线路')],
      ),
    );
  }

  Widget _segment(BuildContext context, int index, String label) {
    final active = value == index;
    return Expanded(
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
    );
  }
}

class _ScoringCard extends StatelessWidget {
  const _ScoringCard({required this.board});
  final RankingBoard board;
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
                  me == null ? '完成线路，加入本月榜' : '我的排名 #${me.rank}',
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
    final medal = switch (entry.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '${entry.rank}',
    };
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
            SizedBox(
              width: 34,
              child: Text(
                medal,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
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

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.rank, required this.route});
  final int rank;
  final RankedRoute route;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WanpanColors.coralSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                route.grade,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: WanpanColors.coralStrong),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$rank. ${route.routeName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${route.gymName}${route.wallZone == null ? '' : ' · ${route.wallZone}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            Column(
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
            ),
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
  });
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 34,
              color: WanpanColors.ink,
            ),
            const SizedBox(height: 8),
            const WanpanMascot(
              asset: AppAssets.mascotCelebrate,
              width: 178,
              height: 168,
              radius: 36,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
