import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/notification_models.dart';
import '../../core/models/user_models.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_skeleton.dart';
import '../../shared/widgets/wanpan_states.dart';
import 'application/notifications_controller.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.controller, super.key});

  final NotificationsController controller;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _openingId;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.refresh());
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    WanpanNotice.show(context, message);
  }

  Future<void> _openNotification(AppNotificationItem item) async {
    if (_openingId != null) return;
    setState(() => _openingId = item.id);
    try {
      await widget.controller.markRead(item);
      if (!mounted) return;
      final route = item.route;
      if (route != null) {
        await context.push(route);
        if (mounted) await widget.controller.refresh();
      }
    } catch (_) {
      _notice('消息暂时没有打开，请稍后重试');
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await widget.controller.markAllRead();
      _notice('全部消息已读');
    } catch (_) {
      _notice('已读状态没有保存，请稍后重试');
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openProfile(UserSummary user) async {
    await context.push('/users/${Uri.encodeComponent(user.id)}');
    if (mounted) await widget.controller.refresh();
  }

  Future<void> _accept(UserSummary user) async {
    if (widget.controller.isAccepting(user.id)) return;
    try {
      await widget.controller.acceptFriendRequest(user.id);
      _notice('已经成为岩友啦');
    } catch (_) {
      _notice('通过申请失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final hasContent =
          controller.items.isNotEmpty || controller.requests.isNotEmpty;
      final compactAction =
          MediaQuery.sizeOf(context).width < 360 ||
          MediaQuery.textScalerOf(context).scale(14) > 19;
      return Scaffold(
        appBar: AppBar(
          title: const Text('消息'),
          toolbarHeight: (MediaQuery.textScalerOf(context).scale(20) + 20)
              .clamp(kToolbarHeight, double.infinity),
          actions: [
            if (controller.unreadCount > 0 || _markingAll)
              if (compactAction || _markingAll)
                IconButton(
                  key: const Key('notifications-mark-all-read'),
                  tooltip: '全部已读',
                  onPressed: _markingAll ? null : _markAllRead,
                  icon: _markingAll
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all_rounded),
                )
              else
                TextButton(
                  key: const Key('notifications-mark-all-read'),
                  onPressed: _markAllRead,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: const Text('全部已读'),
                ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              key: const Key('notifications-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (controller.loading && hasContent)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      semanticsLabel: '正在刷新消息',
                    ),
                  ),
                if (controller.error != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _RefreshError(
                        message: controller.error!,
                        onRetry: controller.loading ? null : controller.refresh,
                      ),
                    ),
                  ),
                if (controller.loading && !hasContent)
                  const SliverPadding(
                    padding: EdgeInsets.all(20),
                    sliver: SliverToBoxAdapter(child: _LoadingMessages()),
                  )
                else if (!hasContent && controller.error == null)
                  const SliverToBoxAdapter(
                    child: WanpanEmptyState(
                      key: Key('notifications-empty'),
                      title: '还没有消息',
                      description: '岩友申请和新的互动，都会出现在这里。',
                    ),
                  ),
                if (controller.requests.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    sliver: SliverList.list(
                      children: [
                        Text(
                          '岩友申请',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        for (final user in controller.requests) ...[
                          _FriendRequestCard(
                            key: Key('notification-request-${user.id}'),
                            user: user,
                            accepting: controller.isAccepting(user.id),
                            onOpenProfile: () => _openProfile(user),
                            onAccept: () => _accept(user),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                if (controller.items.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '消息记录',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.separated(
                      itemCount: controller.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final item = controller.items[index];
                        return _NotificationCard(
                          key: Key('notification-${item.id}'),
                          item: item,
                          opening: _openingId == item.id,
                          onTap: _openingId == null
                              ? () => _openNotification(item)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _FriendRequestCard extends StatelessWidget {
  const _FriendRequestCard({
    required this.user,
    required this.accepting,
    required this.onOpenProfile,
    required this.onAccept,
    super.key,
  });

  final UserSummary user;
  final bool accepting;
  final VoidCallback onOpenProfile;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => WanpanCard(
    padding: const EdgeInsets.all(16),
    hasShadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RequestAvatar(user: user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.nickname,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('想和你成为岩友', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final profile = WanpanButton(
              key: Key('notification-profile-${user.id}'),
              label: '查看主页',
              semanticLabel: '查看${user.nickname}的主页',
              style: WanpanButtonStyle.secondary,
              onPressed: onOpenProfile,
            );
            final accept = WanpanButton(
              key: Key('notification-accept-${user.id}'),
              label: '通过',
              semanticLabel: '通过${user.nickname}的岩友申请',
              loading: accepting,
              onPressed: accepting ? null : onAccept,
            );
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 19) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [profile, const SizedBox(height: 12), accept],
              );
            }
            return Row(
              children: [
                Expanded(child: profile),
                const SizedBox(width: 12),
                Expanded(child: accept),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _RequestAvatar extends StatelessWidget {
  const _RequestAvatar({required this.user});

  final UserSummary user;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      AppAssets.mascotWelcome,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: WanpanColors.surfaceMuted,
        child: Icon(Icons.person_rounded, color: WanpanColors.inkSecondary),
      ),
    );
    final avatarUrl = user.avatarUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox.square(
        dimension: 48,
        child: avatarUrl == null || avatarUrl.isEmpty
            ? fallback
            : Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                cacheWidth: 144,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.opening,
    required this.onTap,
    super.key,
  });

  final AppNotificationItem item;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    padding: const EdgeInsets.all(16),
    hasShadow: false,
    borderColor: item.isUnread ? WanpanColors.coral : WanpanColors.border,
    onTap: onTap,
    semanticLabel: '${item.isUnread ? '未读' : '已读'}，${item.title}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (opening) ...[
              const SizedBox(width: 12),
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ] else if (item.isUnread) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  key: Key('notification-unread-${item.id}'),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: WanpanColors.coral,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (item.content?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(item.content!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        if (item.createdAt != null) ...[
          const SizedBox(height: 12),
          Text(
            _formatDate(item.createdAt!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );
}

class _RefreshError extends StatelessWidget {
  const _RefreshError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => WanpanCard(
    key: const Key('notifications-error'),
    padding: const EdgeInsets.all(16),
    hasShadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          child: const Text('重新加载'),
        ),
      ],
    ),
  );
}

class _LoadingMessages extends StatelessWidget {
  const _LoadingMessages();

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载消息',
    child: Column(
      children: [
        for (var index = 0; index < 3; index++) ...[
          const WanpanCard(
            hasShadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WanpanSkeleton(height: 20),
                SizedBox(height: 12),
                WanpanSkeleton(height: 16),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );
}

String _formatDate(DateTime value) {
  final date = value.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}
