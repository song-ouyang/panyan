import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/feed_repository.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_states.dart';
import '../../shared/widgets/wanpan_video_cover.dart';
import '../auth/application/session_controller.dart';

enum MyActivityKind { comments, favorites, likes }

extension on MyActivityKind {
  String get title => switch (this) {
    MyActivityKind.comments => '我的评论',
    MyActivityKind.favorites => '我的收藏',
    MyActivityKind.likes => '我的点赞',
  };

  String get emptyTitle => switch (this) {
    MyActivityKind.comments => '还没有发出评论',
    MyActivityKind.favorites => '还没有收藏动态',
    MyActivityKind.likes => '还没有点赞动态',
  };

  String get emptyDescription => switch (this) {
    MyActivityKind.comments => '和岩友交流后，你发出的评论会出现在这里。',
    MyActivityKind.favorites => '遇到想再看的动态，点一下收藏就能留在这里。',
    MyActivityKind.likes => '给喜欢的动态点个赞，以后可以在这里找到。',
  };

  String get removeLabel => switch (this) {
    MyActivityKind.comments => '删除评论',
    MyActivityKind.favorites => '取消收藏',
    MyActivityKind.likes => '取消点赞',
  };

  String get removedLabel => switch (this) {
    MyActivityKind.comments => '评论已删除',
    MyActivityKind.favorites => '已取消收藏',
    MyActivityKind.likes => '已取消点赞',
  };
}

class MyActivityScreen extends StatefulWidget {
  const MyActivityScreen({
    super.key,
    required this.api,
    required this.session,
    required this.kind,
  });

  final ApiClient api;
  final SessionController session;
  final MyActivityKind kind;

  @override
  State<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends State<MyActivityScreen> {
  late ProfileRepository _profileRepository;
  late FeedRepository _feedRepository;
  List<_ActivityEntry> _items = const [];
  String? _nextCursor;
  String? _error;
  String? _pageError;
  String? _busyId;
  String? _token;
  String? _userId;
  bool _refreshing = true;
  bool _loadingMore = false;
  bool _confirming = false;
  bool _refreshAfterMutation = false;
  int _sessionRevision = 0;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _bind();
    _refresh();
  }

  void _bind() {
    _profileRepository = ProfileRepository(widget.api);
    _feedRepository = FeedRepository(widget.api);
    _token = widget.session.token;
    _userId = widget.session.user?.id;
    widget.session.addListener(_handleSessionChanged);
    widget.api.socialActivity.addListener(_handleActivityChanged);
  }

  @override
  void didUpdateWidget(covariant MyActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api == widget.api &&
        oldWidget.session == widget.session &&
        oldWidget.kind == widget.kind) {
      return;
    }
    oldWidget.session.removeListener(_handleSessionChanged);
    oldWidget.api.socialActivity.removeListener(_handleActivityChanged);
    _bind();
    _reset();
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    widget.api.socialActivity.removeListener(_handleActivityChanged);
    super.dispose();
  }

  bool _isCurrentSession(int revision) =>
      mounted &&
      revision == _sessionRevision &&
      widget.session.isAuthenticated &&
      widget.session.token == _token &&
      widget.session.user?.id == _userId;

  void _handleSessionChanged() {
    if (_token == widget.session.token && _userId == widget.session.user?.id) {
      return;
    }
    _token = widget.session.token;
    _userId = widget.session.user?.id;
    _reset();
  }

  void _reset() {
    ++_sessionRevision;
    ++_loadRevision;
    setState(() {
      _items = const [];
      _nextCursor = null;
      _error = null;
      _pageError = null;
      _busyId = null;
      _refreshing = widget.session.isAuthenticated;
      _loadingMore = false;
      _refreshAfterMutation = false;
    });
    if (widget.session.isAuthenticated) _refresh();
  }

  void _handleActivityChanged() {
    if (!widget.session.isAuthenticated) return;
    final changes = widget.api.socialActivity;
    final postId = changes.changedPostId;
    if (postId == null) {
      // Friendship/block changes can revoke access to every cached parent post.
      ++_loadRevision;
      setState(() {
        _items = const [];
        _nextCursor = null;
        _error = null;
        _pageError = null;
        _loadingMore = false;
        _refreshing = true;
      });
    } else if (changes.postDeleted) {
      ++_loadRevision;
      setState(
        () => _items = _items.where((item) => item.post.id != postId).toList(),
      );
    }
    _refresh();
  }

  Future<({List<_ActivityEntry> items, String? cursor})> _fetch(
    String? cursor,
  ) async {
    if (widget.kind == MyActivityKind.comments) {
      final page = await _profileRepository.getMyComments(cursor: cursor);
      return (
        items: page.items
            .map(
              (comment) => _ActivityEntry(post: comment.post, comment: comment),
            )
            .toList(),
        cursor: page.nextCursor,
      );
    }
    final page = widget.kind == MyActivityKind.favorites
        ? await _profileRepository.getMyFavorites(cursor: cursor)
        : await _profileRepository.getMyLikes(cursor: cursor);
    return (
      items: page.items.map((post) => _ActivityEntry(post: post)).toList(),
      cursor: page.nextCursor,
    );
  }

  Future<void> _refresh() async {
    if (!widget.session.isAuthenticated) {
      setState(() => _refreshing = false);
      return;
    }
    if (_busyId != null) {
      _refreshAfterMutation = true;
      return;
    }
    final sessionRevision = _sessionRevision;
    final revision = ++_loadRevision;
    setState(() {
      _refreshing = true;
      _loadingMore = false;
      _error = null;
      _pageError = null;
    });
    try {
      final page = await _fetch(null);
      if (!_isCurrentSession(sessionRevision) || revision != _loadRevision) {
        return;
      }
      setState(() {
        _items = page.items;
        _nextCursor = page.cursor;
        _refreshing = false;
      });
    } catch (_) {
      if (!_isCurrentSession(sessionRevision) || revision != _loadRevision) {
        return;
      }
      setState(() {
        _refreshing = false;
        _error = _items.isEmpty ? '记录暂时没有加载出来' : '刷新失败，仍保留已有记录';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final sessionRevision = _sessionRevision;
    if (cursor == null ||
        _refreshing ||
        _loadingMore ||
        _busyId != null ||
        !_isCurrentSession(sessionRevision)) {
      return;
    }
    final revision = _loadRevision;
    setState(() {
      _loadingMore = true;
      _pageError = null;
    });
    try {
      final page = await _fetch(cursor);
      if (!_isCurrentSession(sessionRevision) || revision != _loadRevision) {
        return;
      }
      final existingIds = _items.map((item) => item.id).toSet();
      setState(() {
        _items = [
          ..._items,
          ...page.items.where((item) => existingIds.add(item.id)),
        ];
        _nextCursor = page.cursor == cursor ? null : page.cursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!_isCurrentSession(sessionRevision) || revision != _loadRevision) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _pageError = '后面的记录暂时没有加载出来';
      });
    }
  }

  Future<void> _open(_ActivityEntry item) async {
    final revision = _sessionRevision;
    if (_busyId == item.id || !_isCurrentSession(revision)) return;
    await context.push<void>('/posts/${item.post.id}');
    if (_isCurrentSession(revision)) await _refresh();
  }

  Future<void> _remove(_ActivityEntry item) async {
    final revision = _sessionRevision;
    if (_busyId != null || _confirming || !_isCurrentSession(revision)) return;
    if (item.comment != null) {
      _confirming = true;
      bool confirmed;
      try {
        confirmed = await _confirmCommentDeletion();
      } finally {
        _confirming = false;
      }
      if (!confirmed || !_isCurrentSession(revision)) return;
    }
    // Reads begun before this write cannot restore the old interaction state.
    ++_loadRevision;
    setState(() {
      _busyId = item.id;
      _refreshing = false;
      _loadingMore = false;
      _refreshAfterMutation = false;
    });
    var changed = false;
    try {
      switch (widget.kind) {
        case MyActivityKind.comments:
          await _feedRepository.deleteComment(item.post.id, item.comment!.id);
        case MyActivityKind.favorites:
          if (await _feedRepository.setFavorited(
            item.post.id,
            favorited: false,
          )) {
            throw StateError('Favorite was not removed');
          }
        case MyActivityKind.likes:
          if (await _feedRepository.setLiked(item.post.id, liked: false)) {
            throw StateError('Like was not removed');
          }
      }
      if (!_isCurrentSession(revision)) return;
      changed = true;
      setState(
        () => _items = _items.where((entry) => entry.id != item.id).toList(),
      );
      _notice(widget.kind.removedLabel);
    } catch (_) {
      if (_isCurrentSession(revision)) {
        _notice('${widget.kind.removeLabel}失败，请稍后重试');
      }
    } finally {
      if (_isCurrentSession(revision)) {
        final refresh = changed || _refreshAfterMutation;
        setState(() {
          _busyId = null;
          _refreshAfterMutation = false;
        });
        if (refresh) await _refresh();
      }
    }
  }

  Future<bool> _confirmCommentDeletion() async =>
      await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('删除这条评论？', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('这条评论会从动态中删除，删除后无法恢复。'),
              const SizedBox(height: 20),
              WanpanButton(
                label: '确认删除',
                style: WanpanButtonStyle.danger,
                onPressed: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: 8),
              WanpanButton(
                label: '取消',
                style: WanpanButtonStyle.quiet,
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ) ??
      false;

  void _notice(String text) => WanpanNotice.show(context, text);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.kind.title)),
    body: _content(),
  );

  Widget _content() {
    if (!widget.session.isAuthenticated) {
      return SingleChildScrollView(
        child: Center(
          child: WanpanEmptyState(title: '登录后查看${widget.kind.title}'),
        ),
      );
    }
    if (_refreshing && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    if (_error != null && _items.isEmpty) {
      return SingleChildScrollView(
        child: Center(
          child: WanpanErrorState(title: _error!, onRetry: _refresh),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: WanpanEmptyState(
                  title: widget.kind.emptyTitle,
                  description: widget.kind.emptyDescription,
                ),
              ),
            )
          else ...[
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: Text(_error!)),
                      TextButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              sliver: SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final item = _items[index];
                  return _ActivityCard(
                    key: ValueKey(item.id),
                    item: item,
                    kind: widget.kind,
                    busy: _busyId == item.id,
                    onOpen: _busyId == item.id ? null : () => _open(item),
                    onRemove: _busyId == null ? () => _remove(item) : null,
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  children: [
                    if (_pageError != null) Text(_pageError!),
                    if (_loadingMore)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_nextCursor != null)
                      TextButton(
                        key: const Key('activity-load-more'),
                        onPressed: _refreshing || _busyId != null
                            ? null
                            : _loadMore,
                        child: Text(_pageError == null ? '加载更多' : '重试加载'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityEntry {
  const _ActivityEntry({required this.post, this.comment});
  final FeedPost post;
  final MyComment? comment;
  String get id => comment?.id ?? post.id;
  DateTime? get date => comment?.createdAt ?? post.activityAt ?? post.sentAt;
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    super.key,
    required this.item,
    required this.kind,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
  });
  final _ActivityEntry item;
  final MyActivityKind kind;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final post = item.post;
    final comment = item.comment;
    final author = post.user?.nickname ?? '岩友';
    final date = item.date?.toLocal();
    final dateText = date == null
        ? null
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.'
              '${date.day.toString().padLeft(2, '0')}';
    return WanpanCard(
      hasShadow: false,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (comment == null) ...[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: WanpanColors.coralSoft,
                  backgroundImage: post.user?.avatarUrl == null
                      ? null
                      : ResizeImage.resizeIfNeeded(
                          112,
                          112,
                          NetworkImage(post.user!.avatarUrl!),
                        ),
                  child: post.user?.avatarUrl == null
                      ? Text(author.isEmpty ? '岩' : author.characters.first)
                      : null,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment == null ? author : '我发出的评论',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (dateText != null)
                      Text(
                        dateText,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                  ],
                ),
              ),
              IconButton(
                key: Key('activity-remove-${item.id}'),
                tooltip: kind.removeLabel,
                onPressed: onRemove,
                color: comment == null
                    ? WanpanColors.coralStrong
                    : WanpanColors.inkSecondary,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(switch (kind) {
                        MyActivityKind.comments => Icons.delete_outline_rounded,
                        MyActivityKind.favorites => Icons.star_rounded,
                        MyActivityKind.likes => Icons.favorite_rounded,
                      }),
              ),
            ],
          ),
          InkWell(
            key: Key('activity-open-${item.id}'),
            onTap: onOpen,
            borderRadius: BorderRadius.circular(WanpanRadii.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (comment != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    comment.content,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (comment.moderationStatus == 'pending')
                    Text(
                      '处理中 · 仅自己可见',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  if (comment.moderationStatus == 'rejected')
                    Text('未公开', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: comment == null
                      ? EdgeInsets.zero
                      : const EdgeInsets.all(12),
                  decoration: comment == null
                      ? null
                      : BoxDecoration(
                          color: WanpanColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (comment != null) ...[
                        Text(
                          '$author 的动态',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (post.routeId != null) ...[
                        Text(
                          [
                            post.grade,
                            post.routeName,
                            post.gymName,
                          ].whereType<String>().join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (post.caption?.isNotEmpty == true)
                        Text(
                          post.caption!,
                          maxLines: comment == null ? 5 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (post.videoUrl?.isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        WanpanVideoCover(url: post.videoUrl!),
                      ] else if (post.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              post.imageUrls.first,
                              fit: BoxFit.cover,
                              cacheWidth: 720,
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
                        if (post.imageUrls.length > 1)
                          Text(
                            '共 ${post.imageUrls.length} 张照片',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '查看动态',
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
          ),
        ],
      ),
    );
  }
}
