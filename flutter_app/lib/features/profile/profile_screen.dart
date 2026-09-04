import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
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
  late bool _wasAuthenticated;

  @override
  void initState() {
    super.initState();
    _wasAuthenticated = widget.session.isAuthenticated;
    widget.session.addListener(_handleSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    final authenticated = widget.session.isAuthenticated;
    if (authenticated == _wasAuthenticated) return;
    _wasAuthenticated = authenticated;
    if (authenticated) {
      _load();
    } else if (mounted) {
      setState(() {
        _profile = null;
        _loading = false;
        _error = null;
      });
    }
  }

  Future<void> _load() async {
    if (!widget.session.isAuthenticated) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = UserProfile.fromJson(
        await widget.api.getJson('/users/me'),
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _ProfileHeader(profile: profile, onEdit: _openProfileEditor),
          const SizedBox(height: 18),
          _GrowthCard(
            stats: profile.stats,
            onTap: () => context.push<void>('/profile/calendar'),
          ),
          const SizedBox(height: 22),
          Text('我的攀岩', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.alt_route_rounded,
            title: '线路发布记录',
            subtitle: '查看已发布线路与历史记录',
            onTap: () => context.push('/route-submissions'),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.people_outline_rounded,
            title: '我的岩友',
            subtitle: '看看谁最近也在上墙',
            onTap: () => context.push('/friends'),
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
          padding: EdgeInsets.fromLTRB(18, 18, compact ? 18 : 10, 16),
          decoration: BoxDecoration(
            color: WanpanColors.skySoft,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: WanpanColors.sky.withValues(alpha: .4)),
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
                    Text(
                      user.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.bio?.isNotEmpty == true ? user.bio! : '每一次上墙，都算成长。',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 9),
                    WanpanPressable(
                      key: const Key('profile-edit-button'),
                      semanticLabel: '编辑个人资料',
                      onTap: onEdit,
                      pressedScale: .97,
                      borderRadius: BorderRadius.circular(WanpanRadii.pill),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .78),
                          borderRadius: BorderRadius.circular(WanpanRadii.pill),
                          border: Border.all(
                            color: WanpanColors.sky.withValues(alpha: .55),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: WanpanColors.inkSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '编辑资料',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                const WanpanMascot(
                  asset: AppAssets.mascotWelcome,
                  width: 72,
                  height: 86,
                  radius: 22,
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: WanpanColors.coralSoft,
          borderRadius: BorderRadius.circular(WanpanRadii.large),
          border: Border.all(color: const Color(0x33F2674F)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .72),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    color: WanpanColors.coral,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本月攀爬进度',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '点开查看攀岩日历',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WanpanColors.coralStrong,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(value: '${stats.monthlySends}', label: '本月完攀'),
                ),
                Expanded(
                  child: _Stat(
                    value: 'V${stats.monthlyMaxGrade}',
                    label: '本月最高',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: WanpanColors.coral.withValues(alpha: .2)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Stat(value: '${stats.totalSends}', label: '累计完攀'),
                ),
                const SizedBox(height: 46, child: VerticalDivider()),
                Expanded(
                  child: _Stat(value: 'V${stats.maxGrade}', label: '最高难度'),
                ),
                const SizedBox(height: 46, child: VerticalDivider()),
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
      child: Container(
        padding: const EdgeInsets.all(15),
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
