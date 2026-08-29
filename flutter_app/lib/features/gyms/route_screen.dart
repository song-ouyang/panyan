import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/models/gym_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/gym_repository.dart';
import '../auth/application/session_controller.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';
import '../../shared/widgets/wanpan_video_player.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({
    required this.api,
    required this.session,
    required this.routeId,
    super.key,
  });

  final ApiClient api;
  final SessionController session;
  final String routeId;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  late final GymRepository _repository = GymRepository(widget.api);
  ClimbingRoute? _route;
  RouteLeaderboard? _leaderboard;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final route = await _repository.getRoute(widget.routeId);
      RouteLeaderboard? leaderboard;
      if (widget.session.isAuthenticated) {
        leaderboard = await _repository.getRouteLeaderboard(widget.routeId);
      }
      if (!mounted) return;
      setState(() {
        _route = route;
        _leaderboard = leaderboard;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_route?.name ?? '线路详情')),
    body: _body(),
    bottomNavigationBar: _route == null
        ? null
        : SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: WanpanButton(
              label: widget.session.isAuthenticated ? '我完攀了' : '登录后打卡',
              icon: const Icon(Icons.videocam_rounded),
              onPressed: _checkin,
            ),
          ),
  );

  Future<void> _checkin() async {
    final route = _route;
    if (route == null) return;
    final completed = await context.push<bool>(
      '/routes/${route.id}/checkin',
      extra: <String, String>{'name': route.name, 'grade': route.grade},
    );
    if (completed == true && mounted) await _load();
  }

  Widget _body() {
    if (_route == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            WanpanSkeleton(height: 240, borderRadius: 24),
            SizedBox(height: 18),
            WanpanSkeleton(height: 28),
            SizedBox(height: 12),
            WanpanSkeleton(width: 180),
          ],
        ),
      );
    }
    if (_route == null) {
      return WanpanErrorState(title: '线路详情没有加载出来', onRetry: _load);
    }
    final route = _route!;
    return RefreshIndicator(
      onRefresh: _load,
      color: WanpanColors.coral,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _RouteHero(route: route),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: WanpanColors.coral,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: WanpanColors.coralStrong,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  route.grade,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (route.gymName != null) route.gymName!,
                        if (route.wallZone != null) route.wallZone!,
                        if (route.routeSetName != null) route.routeSetName!,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (route.featuredSend?.videoUrl?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 22),
            RouteFeaturedVideo(
              post: route.featuredSend!,
              onOpenProfile: route.featuredSend!.user == null
                  ? null
                  : () =>
                        context.push('/users/${route.featuredSend!.user!.id}'),
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Text('完攀视频榜', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text(
                '${_leaderboard?.completionCount ?? route.sendCount} 人完攀',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: WanpanColors.coralStrong),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!widget.session.isAuthenticated)
            const WanpanEmptyState(
              title: '登录后查看视频排名',
              description: '点赞越多，完攀视频排名越靠前。',
              imageAsset: null,
            )
          else if ((_leaderboard?.items ?? const []).isEmpty)
            const WanpanEmptyState(
              title: '成为第一个完攀的人',
              description: '上传视频打卡，就能出现在这条线路的榜单上。',
            )
          else
            ..._leaderboard!.items.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LeaderboardCard(
                  entry: entry,
                  onTap: () => context.push('/posts/${entry.post.id}'),
                  onOpenProfile: entry.post.user == null
                      ? null
                      : () => context.push('/users/${entry.post.user!.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RouteFeaturedVideo extends StatelessWidget {
  const RouteFeaturedVideo({
    required this.post,
    super.key,
    this.onOpenProfile,
    this.videoBuilder,
  });

  final FeedPost post;
  final VoidCallback? onOpenProfile;
  final Widget Function(BuildContext context, String url)? videoBuilder;

  @override
  Widget build(BuildContext context) {
    final user = post.user;
    final videoUrl = post.videoUrl!;
    final visibility = switch (post.visibility) {
      'friends' => '仅岩友可见',
      'private' => '仅自己可见',
      _ => '广场可见',
    };
    final moderation = switch (post.moderationStatus) {
      'pending' => '内容处理中',
      'rejected' => '未公开',
      _ => null,
    };

    return Semantics(
      container: true,
      label: '线路首条可见完攀视频',
      child: WanpanCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WanpanRadii.large),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
                child: Row(
                  children: [
                    WanpanPressable(
                      onTap: onOpenProfile,
                      semanticLabel: user == null
                          ? null
                          : '查看${user.nickname}的主页',
                      borderRadius: BorderRadius.circular(WanpanRadii.pill),
                      child: CircleAvatar(
                        radius: 21,
                        backgroundColor: WanpanColors.coralSoft,
                        foregroundImage: user?.avatarUrl == null
                            ? null
                            : NetworkImage(user!.avatarUrl!),
                        child: Text(user?.nickname.characters.first ?? '岩'),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.nickname ?? '岩友',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '首条完攀 · 尝试 ${post.attempts} 次 · $visibility',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    if (moderation != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: WanpanColors.goldSoft,
                          borderRadius: BorderRadius.circular(WanpanRadii.pill),
                        ),
                        child: Text(
                          moderation,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF8A620E),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              videoBuilder?.call(context, videoUrl) ??
                  WanpanVideoPlayer(url: videoUrl),
              if (post.caption?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 4),
                  child: Text(
                    post.caption!.trim(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      size: 17,
                      color: WanpanColors.coral,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${post.likeCount}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 17,
                      color: WanpanColors.inkSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${post.commentCount}',
                      style: Theme.of(context).textTheme.labelMedium,
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

class _RouteHero extends StatelessWidget {
  const _RouteHero({required this.route});

  final ClimbingRoute route;

  @override
  Widget build(BuildContext context) => Hero(
    tag: 'route-${route.id}',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: route.coverUrl == null
            ? const ColoredBox(
                color: WanpanColors.coralSoft,
                child: Icon(
                  Icons.landscape_rounded,
                  size: 74,
                  color: WanpanColors.coral,
                ),
              )
            : Image.network(
                route.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: WanpanColors.coralSoft,
                  child: Icon(
                    Icons.landscape_rounded,
                    size: 74,
                    color: WanpanColors.coral,
                  ),
                ),
              ),
      ),
    ),
  );
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entry,
    required this.onTap,
    this.onOpenProfile,
  });

  final RouteLeaderboardEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final user = entry.post.user;
    return WanpanCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              entry.rank <= 3
                  ? ['🥇', '🥈', '🥉'][entry.rank - 1]
                  : '${entry.rank}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21),
            ),
          ),
          const SizedBox(width: 10),
          WanpanPressable(
            onTap: onOpenProfile,
            semanticLabel: user == null ? null : '查看${user.nickname}的主页',
            borderRadius: BorderRadius.circular(WanpanRadii.pill),
            child: CircleAvatar(
              radius: 23,
              backgroundColor: WanpanColors.surfaceSoft,
              foregroundImage: user?.avatarUrl == null
                  ? null
                  : NetworkImage(user!.avatarUrl!),
              child: Text(user?.nickname.characters.first ?? '岩'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.nickname ?? '岩友',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '尝试 ${entry.post.attempts} 次',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.favorite_rounded,
            size: 18,
            color: WanpanColors.coral,
          ),
          const SizedBox(width: 5),
          Text(
            '${entry.post.likeCount}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
