import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_cartoon_icon.dart';
import '../../shared/widgets/wanpan_cat_avatar.dart';
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
      return SafeArea(
        key: const ValueKey('error'),
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
          ),
        ),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return SafeArea(
        key: const ValueKey('profile-empty-fallback'),
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
          ),
        ),
      );
    }
    return RefreshIndicator(
      key: ValueKey(profile.user.id),
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _ProfileHeader(profile: profile, onEdit: _openProfileEditor),
          const SizedBox(height: 12),
          const _ActivityShortcuts(),
          const SizedBox(height: 14),
          _GrowthCard(
            stats: profile.stats,
            onTap: () => context.push<void>('/profile/calendar'),
          ),
          const SizedBox(height: 16),
          Semantics(
            key: const Key('profile-climbing-actions'),
            container: true,
            label: '我的攀岩',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WanpanColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: WanpanColors.border, width: 1.5),
              ),
              child: Column(
                children: [
                  _ActionTile(
                    icon: WanpanCartoonIconKind.route,
                    title: '线路发布记录',
                    onTap: () => context.push('/route-submissions'),
                  ),
                  const Divider(indent: 54, endIndent: 14),
                  _ActionTile(
                    icon: WanpanCartoonIconKind.friends,
                    title: '我的岩友',
                    onTap: () => context.push('/friends'),
                  ),
                  const Divider(indent: 54, endIndent: 14),
                  _ActionTile(
                    icon: WanpanCartoonIconKind.invite,
                    title: '邀请好友',
                    onTap: () => context.push('/profile/invite'),
                  ),
                ],
              ),
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
  Widget build(BuildContext context) => const Padding(
    key: Key('profile-activity-shortcuts'),
    padding: EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        _ActivityShortcut(
          name: 'posts',
          label: '动态',
          semanticLabel: '我的动态',
          icon: WanpanCartoonIconKind.post,
          color: WanpanColors.coralSoft,
          depth: Color(0xFFE8AD96),
        ),
        _ActivityShortcut(
          name: 'comments',
          label: '评论',
          semanticLabel: '我的评论',
          icon: WanpanCartoonIconKind.comment,
          color: WanpanColors.mint,
          depth: Color(0xFF6AA57E),
        ),
        _ActivityShortcut(
          name: 'favorites',
          label: '收藏',
          semanticLabel: '我的收藏',
          icon: WanpanCartoonIconKind.favorite,
          color: WanpanColors.sunflowerSoft,
          depth: Color(0xFFD7A743),
        ),
        _ActivityShortcut(
          name: 'likes',
          label: '点赞',
          semanticLabel: '我的点赞',
          icon: WanpanCartoonIconKind.like,
          color: WanpanColors.coral,
          depth: WanpanColors.coralStrong,
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
    required this.color,
    required this.depth,
  });

  final String name;
  final String label;
  final String semanticLabel;
  final WanpanCartoonIconKind icon;
  final Color color;
  final Color depth;

  @override
  Widget build(BuildContext context) => Expanded(
    child: WanpanPressable(
      key: Key('profile-activity-$name'),
      semanticLabel: semanticLabel,
      onTap: () => context.push('/profile/$name'),
      enableHaptics: true,
      pressedScale: .97,
      pressedOffset: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WanpanColors.catBlack, width: 1.8),
                boxShadow: [
                  const BoxShadow(
                    color: WanpanColors.catBlack,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(color: depth, offset: const Offset(0, 2)),
                ],
              ),
              child: WanpanCartoonIcon(kind: icon, size: 34),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: WanpanColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: WanpanColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: WanpanColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              WanpanCatAvatar(
                diameter: compact ? 56 : 60,
                image: user.avatarUrl == null
                    ? null
                    : NetworkImage(user.avatarUrl!),
                placeholder: Text(
                  user.nickname.isEmpty ? '岩' : user.nickname.characters.first,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: WanpanColors.coralStrong,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
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
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 0 : 10,
                              ),
                              alignment: Alignment.center,
                              decoration: compact
                                  ? null
                                  : BoxDecoration(
                                      color: WanpanColors.surfaceSoft,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: WanpanColors.border,
                                      ),
                                    ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.edit_outlined,
                                    size: 17,
                                    color: WanpanColors.inkSecondary,
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '编辑资料',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: WanpanColors.inkSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      user.bio?.isNotEmpty == true ? user.bio! : '每一次上墙，都算成长。',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
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
    const radius = BorderRadius.all(Radius.circular(24));
    return WanpanPressable(
      key: const Key('profile-growth-card'),
      semanticLabel: '查看攀岩日历',
      onTap: onTap,
      enableHaptics: true,
      pressedScale: .985,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: radius,
          border: Border.all(color: WanpanColors.border, width: 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              left: -4,
              top: -5,
              child: _RecordHold(color: WanpanColors.coral),
            ),
            const Positioned(
              right: -3,
              bottom: -4,
              child: _RecordHold(color: WanpanColors.grape),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '攀岩记录',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '看日历',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: WanpanColors.coralStrong,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: WanpanColors.coralStrong,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          value: '${stats.totalSends}',
                          label: '完攀线路',
                        ),
                      ),
                      const SizedBox(
                        height: 40,
                        child: VerticalDivider(width: 1),
                      ),
                      Expanded(
                        child: _Stat(
                          value: 'V${stats.maxGrade}',
                          label: '最高难度',
                          color: WanpanColors.coralStrong,
                        ),
                      ),
                      const SizedBox(
                        height: 40,
                        child: VerticalDivider(width: 1),
                      ),
                      Expanded(
                        child: _Stat(value: '${stats.gymCount}', label: '去过岩馆'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordHold extends StatelessWidget {
  const _RecordHold({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Transform.rotate(
        angle: -.4,
        child: Container(
          width: 26,
          height: 23,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(13),
            ),
            border: Border.all(color: WanpanColors.catBlack, width: 1.5),
            boxShadow: const [
              BoxShadow(color: WanpanColors.border, offset: Offset(0, 2)),
            ],
          ),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: WanpanColors.catBlack,
              shape: BoxShape.circle,
              border: Border.all(color: WanpanColors.surface, width: .8),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.color = WanpanColors.catBlack,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: WanpanColors.inkSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final WanpanCartoonIconKind icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      onTap: onTap,
      pressedScale: .99,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              WanpanCartoonIcon(kind: icon, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: WanpanColors.ink,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
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
      ),
    );
  }
}
