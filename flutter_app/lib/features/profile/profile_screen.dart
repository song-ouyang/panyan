import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../../shared/motion/wanpan_motion.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
      appBar: AppBar(title: const Text('我的')),
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
    if (profile == null) return const SizedBox.shrink();
    return RefreshIndicator(
      key: ValueKey(profile.user.id),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        children: [
          _ProfileHeader(profile: profile),
          const SizedBox(height: 18),
          _MonthlyCard(stats: profile.stats),
          const SizedBox(height: 14),
          _AllTimeCard(stats: profile.stats),
          const SizedBox(height: 22),
          Text('成长入口', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.edit_outlined,
            title: '编辑个人资料',
            subtitle: '修改头像、昵称和简介',
            onTap: () async {
              await context.push('/profile/setup?editing=true&from=/profile');
              if (mounted) await _load();
            },
          ),
          const SizedBox(height: 10),
          const _ActionTile(
            icon: Icons.calendar_month_outlined,
            title: '攀岩日历',
            subtitle: '按日期回看每次上墙',
          ),
          const SizedBox(height: 10),
          const _ActionTile(
            icon: Icons.bar_chart_rounded,
            title: '难度成长',
            subtitle: '查看各个 V 级的完成趋势',
          ),
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
          const SizedBox(height: 18),
          _ActionTile(
            icon: Icons.logout_rounded,
            title: '退出登录',
            subtitle: '本机的登录凭证会安全移除',
            onTap: () => widget.session.signOut(),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) {
    final user = profile.user;
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: WanpanColors.coralSoft,
          backgroundImage: user.avatarUrl == null
              ? null
              : NetworkImage(user.avatarUrl!),
          child: user.avatarUrl == null
              ? Text(
                  user.nickname.characters.first,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: WanpanColors.coralStrong,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 16),
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
              const SizedBox(height: 4),
              Text(
                user.bio?.isNotEmpty == true ? user.bio! : '每一次上墙，都算成长。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard({required this.stats});
  final UserStats stats;
  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(
                Icons.local_fire_department_rounded,
                color: WanpanColors.coral,
              ),
              const SizedBox(width: 8),
              Text('本月攀爬进度', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Stat(value: '${stats.monthlySends}', label: '完攀'),
              ),
              Expanded(
                child: _Stat(value: 'V${stats.monthlyMaxGrade}', label: '本月最高'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllTimeCard extends StatelessWidget {
  const _AllTimeCard({required this.stats});
  final UserStats stats;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: _Stat(value: '${stats.totalSends}', label: '累计完攀'),
            ),
            const SizedBox(height: 48, child: VerticalDivider()),
            Expanded(
              child: _Stat(value: 'V${stats.maxGrade}', label: '最高难度'),
            ),
            const SizedBox(height: 48, child: VerticalDivider()),
            Expanded(
              child: _Stat(value: '${stats.gymCount}', label: '去过岩馆'),
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
        Text(label, style: Theme.of(context).textTheme.labelMedium),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
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
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: WanpanColors.coralSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 42,
                color: WanpanColors.coral,
              ),
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
