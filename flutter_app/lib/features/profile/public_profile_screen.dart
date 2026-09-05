import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/profile_models.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_content_safety.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_pressable.dart';

enum _ProfileSafetyAction { report, block, unblock }

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    required this.api,
    required this.userId,
    super.key,
  });

  final ApiClient api;
  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late final ProfileRepository _repository = ProfileRepository(widget.api);
  PublicProfile? _profile;
  String? _friendship;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await _repository.getPublicProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _friendship = profile.user.friendship ?? 'none';
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '这位岩友的主页暂时没有加载出来';
      });
    }
  }

  Future<void> _handleFriendship() async {
    if (_submitting) return;
    final friendship = _friendship ?? 'none';
    if (friendship == 'self' || friendship == 'sent') return;
    if (friendship == 'accepted') {
      final confirmed = await _confirmRemove();
      if (confirmed != true || !mounted) return;
    }

    setState(() => _submitting = true);
    try {
      final next = switch (friendship) {
        'received' => await _repository.acceptFriendRequest(widget.userId),
        'accepted' => await _removeFriend(),
        _ => await _repository.sendFriendRequest(widget.userId),
      };
      if (!mounted) return;
      setState(() => _friendship = next);
      _notice(switch (next) {
        'accepted' => '已经成为岩友啦',
        'none' => '已解除岩友关系',
        _ => '岩友申请已发送',
      });
    } catch (_) {
      if (mounted) _notice('操作没有保存，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String> _removeFriend() async {
    await _repository.removeFriend(widget.userId);
    return 'none';
  }

  Future<bool?> _confirmRemove() => showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('解除岩友关系？', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '解除后，对方仅对岩友可见的动态将不再出现在你的朋友圈。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            WanpanButton(
              label: '解除岩友',
              style: WanpanButtonStyle.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            WanpanButton(
              label: '先不解除',
              style: WanpanButtonStyle.quiet,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _handleSafetyAction(_ProfileSafetyAction action) async {
    if (_submitting || _profile == null) return;
    switch (action) {
      case _ProfileSafetyAction.report:
        final reason = await showWanpanReportReasonSheet(
          context,
          subject: '用户',
        );
        if (reason == null || !mounted) return;
        setState(() => _submitting = true);
        try {
          await _repository.report(
            targetType: 'user',
            targetId: widget.userId,
            reason: reason,
          );
          if (mounted) _notice('举报已提交，我们会尽快处理');
        } catch (_) {
          if (mounted) _notice('举报没有提交成功，请稍后重试');
        } finally {
          if (mounted) setState(() => _submitting = false);
        }
      case _ProfileSafetyAction.block:
        final confirmed = await showWanpanBlockConfirmation(
          context,
          nickname: _profile!.user.nickname,
        );
        if (!confirmed || !mounted) return;
        setState(() => _submitting = true);
        try {
          await _repository.blockUser(widget.userId);
          if (!mounted) return;
          setState(() => _friendship = 'blocked_by_me');
          _notice('已拉黑 ${_profile!.user.nickname}');
        } catch (_) {
          if (mounted) _notice('拉黑没有保存，请稍后重试');
        } finally {
          if (mounted) setState(() => _submitting = false);
        }
      case _ProfileSafetyAction.unblock:
        setState(() => _submitting = true);
        try {
          await _repository.unblockUser(widget.userId);
          if (!mounted) return;
          setState(() => _friendship = 'none');
          _notice('已取消拉黑');
        } catch (_) {
          if (mounted) _notice('操作没有保存，请稍后重试');
        } finally {
          if (mounted) setState(() => _submitting = false);
        }
    }
  }

  void _notice(String message) => WanpanNotice.show(context, message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('岩友主页'),
        actions: [
          if (_profile != null && _friendship != 'self')
            PopupMenuButton<_ProfileSafetyAction>(
              tooltip: '用户安全操作',
              enabled: !_submitting,
              onSelected: _handleSafetyAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _ProfileSafetyAction.report,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined),
                    title: Text('举报用户'),
                  ),
                ),
                if (_friendship == 'blocked_by_me')
                  const PopupMenuItem(
                    value: _ProfileSafetyAction.unblock,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_add_alt_1_rounded),
                      title: Text('取消拉黑'),
                    ),
                  )
                else if (_friendship != 'blocked_me' &&
                    _friendship != 'blocked')
                  const PopupMenuItem(
                    value: _ProfileSafetyAction.block,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.block_rounded,
                        color: WanpanColors.danger,
                      ),
                      title: Text(
                        '拉黑该用户',
                        style: TextStyle(color: WanpanColors.danger),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: WanpanMotion.duration(context, WanpanMotion.exit),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    if (_error != null || _profile == null) {
      return _ProfileError(
        key: const ValueKey('error'),
        message: _error ?? '这位岩友暂时不在这里',
        onRetry: _load,
      );
    }

    final profile = _profile!;
    final grouped = <String, List<PublicMonthlyStat>>{};
    for (final item in profile.monthly) {
      grouped.putIfAbsent(item.month, () => []).add(item);
    }

    return RefreshIndicator(
      key: ValueKey(profile.user.id),
      onRefresh: () => _load(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          _ProfileHeader(profile: profile),
          if ((_friendship ?? 'none') != 'self') ...[
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              child: _FriendshipButton(
                key: ValueKey(_friendship),
                friendship: _friendship ?? 'none',
                loading: _submitting,
                onPressed: _handleFriendship,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _StatsCard(stats: profile.stats),
          const SizedBox(height: 26),
          Text('攀岩记录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text('看看最近几个月都在哪里上墙', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (grouped.isEmpty)
            const _MonthlyEmpty()
          else
            ...grouped.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MonthCard(month: entry.key, items: entry.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final user = profile.user;
    return WanpanCard(
      color: WanpanColors.coralSoft,
      borderColor: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            nickname: user.nickname,
            avatarUrl: user.avatarUrl,
            radius: 36,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.nickname,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.bio?.trim().isNotEmpty == true
                        ? user.bio!
                        : '每一次上墙，都算成长。',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendshipButton extends StatelessWidget {
  const _FriendshipButton({
    required this.friendship,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  final String friendship;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (friendship) {
      'sent' => '等待对方确认',
      'received' => '接受岩友申请',
      'accepted' => '已是岩友',
      'blocked_by_me' => '已拉黑',
      'blocked_me' || 'blocked' => '暂时无法添加',
      _ => '加为岩友',
    };
    final style = switch (friendship) {
      'accepted' => WanpanButtonStyle.secondary,
      'sent' ||
      'blocked' ||
      'blocked_by_me' ||
      'blocked_me' => WanpanButtonStyle.quiet,
      _ => WanpanButtonStyle.primary,
    };
    return WanpanButton(
      label: label,
      loading: loading,
      style: style,
      icon: Icon(switch (friendship) {
        'accepted' => Icons.people_rounded,
        'sent' => Icons.schedule_rounded,
        'received' => Icons.person_add_alt_1_rounded,
        _ => Icons.person_add_alt_1_rounded,
      }),
      onPressed:
          friendship == 'sent' ||
              friendship == 'blocked' ||
              friendship == 'blocked_by_me' ||
              friendship == 'blocked_me' ||
              loading
          ? null
          : onPressed,
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    return WanpanCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _Stat(value: '${stats.totalSends}', label: '完攀'),
          ),
          const SizedBox(height: 48, child: VerticalDivider()),
          Expanded(
            child: _Stat(value: 'V${stats.maxGrade}', label: '最高'),
          ),
          const SizedBox(height: 48, child: VerticalDivider()),
          Expanded(
            child: _Stat(value: '${stats.gymCount}', label: '岩馆'),
          ),
        ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: WanpanColors.coralStrong),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month, required this.items});

  final String month;
  final List<PublicMonthlyStat> items;

  @override
  Widget build(BuildContext context) {
    return WanpanCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: WanpanColors.coral,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                _monthLabel(month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.gymName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                      '${item.grade} · ${item.sends} 条',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: WanpanColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _monthLabel(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return value;
    final month = int.tryParse(parts[1]);
    return month == null ? value : '${parts[0]}年$month月';
  }
}

class _MonthlyEmpty extends StatelessWidget {
  const _MonthlyEmpty();

  @override
  Widget build(BuildContext context) {
    return WanpanCard(
      child: Column(
        children: [
          const Icon(
            Icons.landscape_rounded,
            size: 42,
            color: WanpanColors.coral,
          ),
          const SizedBox(height: 10),
          Text('还没有公开的攀岩记录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('下一次上墙后再来看看吧。', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            WanpanPressable(
              onTap: onRetry,
              enableHaptics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  '重新加载',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: WanpanColors.coralStrong),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.nickname,
    required this.avatarUrl,
    required this.radius,
  });

  final String nickname;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: WanpanColors.surface,
      backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
      child: avatarUrl == null
          ? Text(
              nickname.isEmpty ? '岩' : nickname.characters.first,
              style: TextStyle(
                color: WanpanColors.coralStrong,
                fontSize: radius * .72,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}
