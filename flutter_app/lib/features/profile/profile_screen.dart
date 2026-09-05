import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_pressable.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api, required this.session});
  final ApiClient api;
  final SessionController session;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  String? _sessionUserId;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _sessionUserId = widget.session.user?.id;
    widget.session.addListener(_handleSessionChanged);
    widget.api.climbingActivity.addListener(_handleActivityChanged);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    widget.api.climbingActivity.removeListener(_handleActivityChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    final userId = widget.session.user?.id;
    if (userId == _sessionUserId) return;
    _sessionUserId = userId;
    ++_requestId;
    _profile = null;
    if (widget.session.isAuthenticated) {
      _load();
    } else if (mounted) {
      setState(() {
        _profile = null;
        _loading = false;
        _error = null;
      });
    }
  }

  void _handleActivityChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (!widget.session.isAuthenticated) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = _profile == null;
      _error = null;
    });
    try {
      final profile = UserProfile.fromJson(
        await widget.api.getJson('/users/me'),
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '成长记录暂时没有加载出来';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          if (widget.session.isAuthenticated)
            IconButton(
              key: const Key('profile-friends-button'),
              tooltip: '我的岩友',
              onPressed: () => context.push('/friends'),
              icon: const Icon(Icons.people_outline_rounded),
            ),
          Semantics(
            key: const Key('profile-settings-button'),
            button: true,
            label: '设置',
            excludeSemantics: true,
            onTap: () => context.push<void>('/settings'),
            child: IconButton(
              tooltip: '设置',
              onPressed: () => context.push<void>('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: WanpanMotion.duration(context, WanpanMotion.exit),
        child: _content(),
      ),
    );
  }

  Widget _content() {
    if (!widget.session.isAuthenticated) {
      return const _SignedOut(key: ValueKey('signed-out'));
    }
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
              Icons.cloud_off_rounded,
              size: 52,
              color: WanpanColors.muted,
            ),
            const SizedBox(height: 14),
            Text(_error!, style: Theme.of(context).textTheme.titleMedium),
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return Center(
        key: const ValueKey('profile-empty-fallback'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: WanpanColors.muted,
            ),
            const SizedBox(height: 14),
            Text(
              '成长记录暂时没有加载出来',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      key: ValueKey(profile.user.id),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _ProfileHeader(profile: profile, onEdit: _openProfileEditor),
          const SizedBox(height: 16),
          const _ActivityShortcuts(),
          const SizedBox(height: 16),
          _GrowthCard(
            stats: profile.stats,
            onTap: () => context.push<void>('/profile/calendar'),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '我的攀岩',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: WanpanColors.inkSecondary),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: WanpanColors.surface,
              borderRadius: BorderRadius.circular(WanpanRadii.large),
              border: Border.all(color: WanpanColors.border),
            ),
            child: Column(
              children: [
                _ActionTile(
                  icon: Icons.alt_route_rounded,
                  title: '线路发布记录',
                  subtitle: '查看已发布线路与历史记录',
                  onTap: () => context.push('/route-submissions'),
                ),
                const Divider(indent: 73, endIndent: 16),
                _ActionTile(
                  icon: Icons.people_outline_rounded,
                  title: '我的岩友',
                  subtitle: '看看谁最近也在上墙',
                  onTap: () => context.push('/friends'),
                ),
                const Divider(indent: 73, endIndent: 16),
                _ActionTile(
                  icon: Icons.qr_code_rounded,
                  title: '邀请好友',
                  subtitle: '扫码或分享链接，一起记录完攀',
                  onTap: () => context.push('/profile/invite'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfileEditor() async {
    await context.push<void>('/profile/setup?editing=true&from=/profile');
    if (mounted && widget.session.isAuthenticated) await _load();
  }
}

class _ActivityShortcuts extends StatelessWidget {
  const _ActivityShortcuts();

  @override
  Widget build(BuildContext context) => const WanpanCard(
    key: Key('profile-activity-shortcuts'),
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    hasShadow: false,
    child: Row(
      children: [
        _ActivityShortcut(
          name: 'posts',
          label: '动态',
          semanticLabel: '我的动态',
          icon: Icons.article_outlined,
        ),
        _ActivityShortcut(
          name: 'comments',
          label: '评论',
          semanticLabel: '我的评论',
          icon: Icons.chat_bubble_outline_rounded,
        ),
        _ActivityShortcut(
          name: 'favorites',
          label: '收藏',
          semanticLabel: '我的收藏',
          icon: Icons.bookmark_border_rounded,
        ),
        _ActivityShortcut(
          name: 'likes',
          label: '点赞',
          semanticLabel: '我的点赞',
          icon: Icons.favorite_border_rounded,
        ),
      ],
    ),
  );
}

class _ActivityShortcut extends StatelessWidget {
  const _ActivityShortcut({
    required this.name,
    required this.label,
    required this.semanticLabel,
    required this.icon,
  });

  final String name;
  final String label;
  final String semanticLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: WanpanPressable(
      key: Key('profile-activity-$name'),
      semanticLabel: semanticLabel,
      onTap: () => context.push('/profile/$name'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: WanpanColors.coralStrong),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onEdit});

  final UserProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final user = profile.user;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 330 || textScale > 1.15;
        return Container(
          key: const Key('profile-header-card'),
          padding: EdgeInsets.fromLTRB(18, 18, compact ? 18 : 14, 18),
          decoration: BoxDecoration(
            color: WanpanColors.surface,
            borderRadius: BorderRadius.circular(WanpanRadii.large),
            border: Border.all(color: WanpanColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: compact ? 32 : 36,
                backgroundColor: WanpanColors.coralSoft,
                backgroundImage: user.avatarUrl == null
                    ? null
                    : ResizeImage.resizeIfNeeded(
                        224,
                        224,
                        NetworkImage(user.avatarUrl!),
                      ),
                child: user.avatarUrl == null
                    ? Text(
                        user.nickname.isEmpty
                            ? '岩'
                            : user.nickname.characters.first,
                        style: TextStyle(
                          fontSize: compact ? 23 : 26,
                          fontWeight: FontWeight.w900,
                          color: WanpanColors.coralStrong,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            user.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Tooltip(
                          message: '编辑个人资料',
                          excludeFromSemantics: true,
                          child: WanpanPressable(
                            key: const Key('profile-edit-button'),
                            semanticLabel: '编辑个人资料',
                            onTap: onEdit,
                            pressedScale: .97,
                            borderRadius: BorderRadius.circular(
                              WanpanRadii.pill,
                            ),
                            child: const SizedBox.square(
                              dimension: 44,
                              child: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: WanpanColors.inkSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.bio?.isNotEmpty == true ? user.bio! : '每一次上墙，都算成长。',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                const WanpanMascot(
                  asset: AppAssets.mascotWelcome,
                  width: 64,
                  height: 76,
                  radius: 18,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GrowthCard extends StatelessWidget {
  const _GrowthCard({required this.stats, required this.onTap});

  final UserStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      key: const Key('profile-growth-card'),
      semanticLabel: '查看攀岩日历',
      onTap: onTap,
      enableHaptics: true,
      pressedScale: .985,
      borderRadius: BorderRadius.circular(WanpanRadii.large),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.large),
          border: Border.all(color: WanpanColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('攀爬进度', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Stat(value: '${stats.totalSends}', label: '完攀线路'),
                ),
                Expanded(
                  child: _Stat(value: 'V${stats.maxGrade}', label: '最高难度'),
                ),
                Expanded(
                  child: _Stat(value: '${stats.gymCount}', label: '去过岩馆'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: WanpanColors.coralStrong),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      pressedScale: .985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: WanpanColors.surfaceSoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: WanpanColors.inkSecondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: WanpanColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WanpanMascot(
              asset: AppAssets.mascotWelcome,
              width: 176,
              height: 168,
              radius: 38,
            ),
            const SizedBox(height: 20),
            Text(
              '登录后保存每一次成长',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '查看完攀统计、最高难度和去过的岩馆。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.go('/login?from=/profile'),
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}
