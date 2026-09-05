import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/feed_repository.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_content_safety.dart';
import '../../shared/widgets/wanpan_states.dart';
import '../../shared/widgets/wanpan_video_cover.dart';
import '../auth/application/session_controller.dart';

class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key, required this.api, required this.session});

  final ApiClient api;
  final SessionController session;

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  late final ProfileRepository _profileRepository;
  late final FeedRepository _feedRepository;
  List<MyPost> _posts = const [];
  final Set<String> _deletedIds = {};
  bool _loading = true;
  bool _confirming = false;
  String? _error;
  String? _deletingId;
  String? _sessionToken;
  String? _sessionUserId;
  int _sessionRevision = 0;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _profileRepository = ProfileRepository(widget.api);
    _feedRepository = FeedRepository(widget.api);
    _sessionToken = widget.session.token;
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

  bool _isCurrentSession(int revision) =>
      mounted &&
      revision == _sessionRevision &&
      widget.session.isAuthenticated &&
      widget.session.token == _sessionToken &&
      widget.session.user?.id == _sessionUserId;

  void _handleSessionChanged() {
    if (_sessionToken == widget.session.token &&
        _sessionUserId == widget.session.user?.id) {
      return;
    }
    _sessionToken = widget.session.token;
    _sessionUserId = widget.session.user?.id;
    ++_sessionRevision;
    ++_loadRevision;
    setState(() {
      _posts = const [];
      _deletedIds.clear();
      _deletingId = null;
      _error = null;
      _loading = widget.session.isAuthenticated;
    });
    if (widget.session.isAuthenticated) _load();
  }

  void _handleActivityChanged() {
    if (widget.session.isAuthenticated) _load();
  }

  Future<void> _load() async {
    if (!widget.session.isAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    final sessionRevision = _sessionRevision;
    final loadRevision = ++_loadRevision;
    setState(() {
      _loading = _posts.isEmpty;
      _error = null;
    });
    try {
      final posts = await _profileRepository.getMyPosts();
      if (!_isCurrentSession(sessionRevision) ||
          loadRevision != _loadRevision) {
        return;
      }
      setState(() {
        // A slow read must not bring back a post whose deletion was confirmed.
        _posts = posts.where((post) => !_deletedIds.contains(post.id)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!_isCurrentSession(sessionRevision) ||
          loadRevision != _loadRevision) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _posts.isEmpty ? '动态暂时没有加载出来' : '刷新失败，仍保留已有动态';
      });
    }
  }

  Future<void> _openPost(MyPost post) async {
    final sessionRevision = _sessionRevision;
    if (_deletingId == post.id || !_isCurrentSession(sessionRevision)) return;
    await context.push<void>('/posts/${post.id}');
    if (_isCurrentSession(sessionRevision)) await _load();
  }

  Future<void> _deletePost(MyPost post) async {
    final sessionRevision = _sessionRevision;
    if (_confirming ||
        _deletingId != null ||
        !_isCurrentSession(sessionRevision)) {
      return;
    }
    _confirming = true;
    bool confirmed;
    try {
      confirmed = await showWanpanDeletePostConfirmation(
        context,
        isCheckin: !post.isMoment,
      );
    } finally {
      _confirming = false;
    }
    if (!confirmed || !_isCurrentSession(sessionRevision)) return;
    setState(() => _deletingId = post.id);
    try {
      await _feedRepository.deletePost(post.id);
      if (!_isCurrentSession(sessionRevision)) return;
      setState(() {
        _deletedIds.add(post.id);
        _posts = _posts.where((item) => item.id != post.id).toList();
      });
      _notice('动态已删除');
    } catch (_) {
      if (_isCurrentSession(sessionRevision)) {
        _notice('删除失败，请稍后重试');
      }
    } finally {
      if (_isCurrentSession(sessionRevision)) {
        setState(() => _deletingId = null);
      }
    }
  }

  void _notice(String message) {
    WanpanNotice.show(context, message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的动态')),
    // Do not animate outgoing private content across an account change.
    body: _content(),
  );

  Widget _content() {
    if (!widget.session.isAuthenticated) {
      return const SingleChildScrollView(
        child: Center(
          child: WanpanEmptyState(
            title: '登录后查看自己的动态',
            description: '你的文字、照片和完攀记录都会保存在这里。',
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    if (_posts.isEmpty && _error != null) {
      return SingleChildScrollView(
        child: Center(
          child: WanpanErrorState(title: _error!, onRetry: _load),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_posts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: WanpanEmptyState(
                  title: '还没有发布动态',
                  description: '在广场记录日常，或完攀一条线路后，再来这里看看。',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              sliver: SliverList.separated(
                itemCount: _posts.length + (_error == null ? 0 : 1),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (_error != null && index == 0) {
                    return Row(
                      children: [
                        Expanded(child: Text(_error!)),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    );
                  }
                  final post = _posts[index - (_error == null ? 0 : 1)];
                  return _MyPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    deleting: _deletingId == post.id,
                    onOpen: _deletingId == post.id
                        ? null
                        : () => _openPost(post),
                    onDelete: _deletingId == null
                        ? () => _deletePost(post)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MyPostCard extends StatelessWidget {
  const _MyPostCard({
    super.key,
    required this.post,
    required this.deleting,
    required this.onOpen,
    required this.onDelete,
  });

  final MyPost post;
  final bool deleting;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${date.year}.${twoDigits(date.month)}.${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visibility = switch (post.visibility) {
      'public' => '公开',
      'friends' => '仅岩友',
      _ => '仅自己',
    };
    final status = switch (post.moderationStatus) {
      'rejected' => '未公开',
      'pending' => '处理中',
      _ => null,
    };
    final video = post.videoUrl;
    return WanpanCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      hasShadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                post.isMoment
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.flag_outlined,
                color: WanpanColors.coralStrong,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  post.isMoment ? '日常动态' : '完攀打卡',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: Key('delete-my-post-${post.id}'),
                tooltip: '删除这条动态',
                onPressed: onDelete,
                icon: deleting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                color: WanpanColors.inkSecondary,
              ),
            ],
          ),
          InkWell(
            key: Key('open-my-post-${post.id}'),
            onTap: onOpen,
            borderRadius: BorderRadius.circular(WanpanRadii.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (post.sentAt != null)
                  Text(
                    _dateLabel(post.sentAt!),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                if (!post.isMoment) ...[
                  const SizedBox(height: 10),
                  Text(
                    [
                      post.grade,
                      post.routeName ?? '完攀记录',
                    ].whereType<String>().join(' · '),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (post.gymName?.isNotEmpty == true)
                    Text(
                      post.gymName!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
                if (post.caption?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    post.caption!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                if (video != null && video.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  WanpanVideoCover(url: video),
                ],
                if (post.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (
                        var i = 0;
                        i < post.imageUrls.length.clamp(0, 3);
                        i++
                      ) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.network(
                                post.imageUrls[i],
                                fit: BoxFit.cover,
                                cacheWidth: 600,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: WanpanColors.surfaceSoft,
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: WanpanColors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _PostLabel(label: visibility),
                    if (status != null) _PostLabel(label: status),
                    if (!post.isMoment)
                      _PostLabel(label: '尝试 ${post.attempts} 次'),
                    if (post.imageUrls.length > 3)
                      _PostLabel(label: '共 ${post.imageUrls.length} 张照片'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '查看详情',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: WanpanColors.muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostLabel extends StatelessWidget {
  const _PostLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WanpanColors.surfaceSoft,
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    ),
  );
}
