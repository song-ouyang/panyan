import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/feed_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_cat_mark.dart';
import '../../shared/widgets/wanpan_cartoon_icon.dart';
import '../../shared/widgets/wanpan_content_safety.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../../shared/widgets/wanpan_video_cover.dart';
import '../auth/application/session_controller.dart';
import '../../shared/motion/wanpan_motion.dart';

typedef _MomentPublishResult = ({String? moderationStatus, String visibility});

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.api, required this.session});

  final ApiClient api;
  final SessionController session;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final FeedRepository _repository = FeedRepository(widget.api);
  final Map<String, List<_FeedEntry>> _scopeCache = {};
  final Map<String, bool> _pendingLikes = {};
  final Map<String, bool> _pendingFavorites = {};
  final Set<String> _deletedPostIds = {};
  final Set<String> _deletingPostIds = {};
  String? _sessionToken;
  String _scope = 'square';
  bool _loading = true;
  String? _error;
  int _loadRevision = 0;

  List<_FeedEntry> get _items => _scopeCache[_scope] ?? const [];

  @override
  void initState() {
    super.initState();
    widget.api.socialActivity.addListener(_handleSocialChanged);
    _sessionToken = widget.session.token;
    widget.session.addListener(_handleSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.api.socialActivity.removeListener(_handleSocialChanged);
    widget.session.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSocialChanged() {
    if (!mounted) return;
    final postId = widget.api.socialActivity.changedPostId;
    if (postId == null) {
      _scopeCache.clear();
      _load(showLoading: true);
    } else {
      if (widget.api.socialActivity.postDeleted) {
        _deletedPostIds.add(postId);
        for (final items in _scopeCache.values) {
          items.removeWhere((entry) => entry.post.id == postId);
        }
      }
      _load();
    }
  }

  void _handleSessionChanged() {
    final token = widget.session.token;
    if (token == _sessionToken) return;
    _sessionToken = token;
    ++_loadRevision;
    _deletedPostIds.clear();
    _deletingPostIds.clear();
    _pendingLikes.clear();
    _pendingFavorites.clear();
    _scopeCache.clear();
    _load(showLoading: true);
  }

  Future<void> _load({bool showLoading = false}) async {
    final scope = _scope;
    final token = widget.session.token;
    final revision = ++_loadRevision;
    if (!widget.session.isAuthenticated && scope == 'friends') {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
      return;
    }
    if (mounted) {
      setState(() {
        _error = null;
        _loading = showLoading || !_scopeCache.containsKey(scope);
      });
    }
    try {
      final posts = (await _repository.getFeed(scope: scope)).items
          .where((post) => !_deletedPostIds.contains(post.id))
          .map((post) {
            final entry = _FeedEntry(post);
            final liked = _pendingLikes[post.id];
            if (liked != null && liked != entry.liked) {
              entry.likeCount = (entry.likeCount + (liked ? 1 : -1)).clamp(
                0,
                1 << 31,
              );
              entry.liked = liked;
            }
            entry.favorited = _pendingFavorites[post.id] ?? entry.favorited;
            return entry;
          })
          .toList();
      if (!mounted ||
          revision != _loadRevision ||
          scope != _scope ||
          token != widget.session.token) {
        return;
      }
      setState(() {
        _scopeCache[scope] = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted ||
          revision != _loadRevision ||
          scope != _scope ||
          token != widget.session.token) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '广场暂时走丢了，稍后再试';
      });
      if (_items.isNotEmpty) _notice('刷新失败，仍为你保留上次内容');
    }
  }

  Future<void> _toggleLike(_FeedEntry entry) =>
      _toggleReaction(entry, favorite: false);

  Future<void> _toggleFavorite(_FeedEntry entry) =>
      _toggleReaction(entry, favorite: true);

  void _applyReaction(String postId, bool value, {required bool favorite}) {
    for (final items in _scopeCache.values) {
      for (final item in items.where((item) => item.post.id == postId)) {
        if (favorite) {
          item.favorited = value;
        } else if (item.liked != value) {
          item.liked = value;
          item.likeCount = (item.likeCount + (value ? 1 : -1)).clamp(
            0,
            1 << 31,
          );
        }
      }
    }
  }

  Future<void> _toggleReaction(
    _FeedEntry entry, {
    required bool favorite,
  }) async {
    final postId = entry.post.id;
    if (_deletingPostIds.contains(postId) || _deletedPostIds.contains(postId)) {
      return;
    }
    if (!widget.session.isAuthenticated) {
      await context.push('/login?from=/feed');
      return;
    }
    final pending = favorite ? _pendingFavorites : _pendingLikes;
    if (pending.containsKey(postId)) return;
    final previous = favorite ? entry.favorited : entry.liked;
    final token = widget.session.token;
    setState(() {
      pending[postId] = !previous;
      _applyReaction(postId, !previous, favorite: favorite);
    });
    try {
      if (favorite) {
        await _repository.setFavorited(postId, favorited: !previous);
      } else {
        await _repository.setLiked(postId, liked: !previous);
      }
    } catch (_) {
      if (!mounted ||
          token != widget.session.token ||
          _deletedPostIds.contains(postId)) {
        return;
      }
      setState(() => _applyReaction(postId, previous, favorite: favorite));
      _notice('操作没有保存，请重试');
    } finally {
      if (mounted && token == widget.session.token) {
        setState(() => pending.remove(postId));
        // Supersede any read begun before the mutation finished.
        _load();
      }
    }
  }

  Future<void> _compose() async {
    if (!widget.session.isAuthenticated) {
      await context.push('/login?from=/feed');
      return;
    }
    final published = await showModalBottomSheet<_MomentPublishResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => _ComposeSheet(
        api: widget.api,
        initialVisibility: _scope == 'square' ? 'public' : 'friends',
      ),
    );
    if (published != null && mounted) {
      if (published.moderationStatus == 'approved') {
        setState(() {
          _scope = published.visibility == 'friends' ? 'friends' : 'square';
          _scopeCache.clear();
        });
      }
      _notice(switch (published.moderationStatus) {
        'approved' => '动态已发布',
        'pending' => '动态已提交，审核后可见',
        'rejected' => '动态未通过，请调整内容后重新发布',
        _ => '动态已提交，刷新后查看',
      });
      await _load();
    }
  }

  Future<void> _openFriends() async {
    if (!widget.session.isAuthenticated) {
      await context.push('/login?from=/feed');
      return;
    }
    await context.push('/friends');
    if (!mounted) return;
    setState(() => _scopeCache.remove('friends'));
    await _load();
  }

  Future<void> _openPost(String postId) async {
    await context.push('/posts/$postId');
    if (mounted) await _load();
  }

  Future<void> _deletePost(FeedPost post) async {
    if (!widget.session.isAuthenticated ||
        post.user?.id != widget.session.user?.id ||
        _deletingPostIds.contains(post.id)) {
      return;
    }
    final token = widget.session.token;
    setState(() => _deletingPostIds.add(post.id));
    try {
      final confirmed = await showWanpanDeletePostConfirmation(
        context,
        isCheckin: post.routeId != null,
      );
      if (!confirmed || !mounted || token != widget.session.token) return;
      await _repository.deletePost(post.id);
      if (!mounted || token != widget.session.token) return;
      setState(() {
        _deletedPostIds.add(post.id);
        for (final items in _scopeCache.values) {
          items.removeWhere((item) => item.post.id == post.id);
        }
      });
      _notice('动态已删除');
    } catch (_) {
      if (mounted && token == widget.session.token) {
        _notice('删除失败，动态仍保留，请稍后重试');
      }
    } finally {
      if (mounted && token == widget.session.token) {
        setState(() => _deletingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _openUser(String userId) async {
    await context.push('/users/$userId');
    if (!mounted) return;
    setState(() => _scopeCache.remove('friends'));
    await _load();
  }

  void _changeScope(String value) {
    if (value == _scope) return;
    if (value == 'friends' && !widget.session.isAuthenticated) {
      context.push('/login?from=/feed');
      return;
    }
    setState(() {
      _scope = value;
      _loading = !_scopeCache.containsKey(value);
      _error = null;
    });
    _load();
  }

  void _notice(String message) {
    WanpanNotice.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('广场'),
        toolbarHeight: 52,
        actions: [
          if (widget.session.isAuthenticated) ...[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: '发布动态',
                child: WanpanPressable(
                  semanticLabel: '发布动态',
                  onTap: _compose,
                  pressedOffset: 3,
                  enableHaptics: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          top: 3,
                          bottom: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: WanpanColors.coral,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: const [
                                BoxShadow(
                                  color: WanpanColors.coralStrong,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 29,
                              color: WanpanColors.surface,
                            ),
                          ),
                        ),
                        const Positioned(
                          top: 0,
                          left: -13,
                          child: IgnorePointer(
                            child: WanpanCatMark(size: 25, peeking: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => context.push('/login?from=/feed'),
                child: const Text('登录'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: _ScopePicker(value: _scope, onChanged: _changeScope),
          ),
          Expanded(
            child: AnimatedSwitcher(
              key: ValueKey(widget.session.user?.id),
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (!widget.session.isAuthenticated && _scope == 'friends') {
      return const _FeedEmpty(
        key: ValueKey('signed-out'),
        icon: Icons.people_alt_outlined,
        title: '登录后查看朋友圈',
        description: '朋友圈只展示你和已成为岩友的人发布的动态。',
      );
    }
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _FeedEmpty(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_rounded,
        title: _error!,
        description: '检查网络后重新加载。',
        action: TextButton(onPressed: _load, child: const Text('再试一次')),
      );
    }
    if (_items.isEmpty) {
      return _FeedEmpty(
        key: ValueKey('empty-$_scope'),
        icon: _scope == 'square'
            ? Icons.auto_awesome_rounded
            : Icons.people_alt_outlined,
        title: _scope == 'square' ? '这里还很安静' : '岩友圈还没有新动态',
        description: _scope == 'square'
            ? '成为第一个分享攀岩瞬间的人吧。'
            : '先加几位岩友，就能看到他们分享的攀岩日常。',
        action: FilledButton(
          onPressed: _scope == 'square' ? _compose : _openFriends,
          child: Text(_scope == 'square' ? '发布动态' : '去加岩友'),
        ),
      );
    }
    return RefreshIndicator(
      key: const ValueKey('list'),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        itemCount: _items.length + (_scope == 'friends' ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (_scope == 'friends' && index == 0) {
            return _FriendsActivityBanner(onTap: _openFriends);
          }
          final itemIndex = index - (_scope == 'friends' ? 1 : 0);
          final entry = _items[itemIndex];
          return _PostCard(
            key: ValueKey(entry.post.id),
            entry: entry,
            onLike: () => _toggleLike(entry),
            liking: _pendingLikes.containsKey(entry.post.id),
            onFavorite: () => _toggleFavorite(entry),
            favoriting: _pendingFavorites.containsKey(entry.post.id),
            onOpen: _deletingPostIds.contains(entry.post.id)
                ? null
                : () => _openPost(entry.post.id),
            onOpenUser: entry.post.user == null
                ? null
                : () => _openUser(entry.post.user!.id),
            onDelete:
                widget.session.isAuthenticated &&
                    entry.post.user?.id == widget.session.user?.id
                ? () => _deletePost(entry.post)
                : null,
            deleting: _deletingPostIds.contains(entry.post.id),
          );
        },
      ),
    );
  }
}

class _FriendsActivityBanner extends StatelessWidget {
  const _FriendsActivityBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    semanticLabel: '我的岩友',
    hasShadow: false,
    color: WanpanColors.sunflowerSoft.withValues(alpha: .42),
    borderColor: WanpanColors.border,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          const WanpanCartoonIcon(
            kind: WanpanCartoonIconKind.friends,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('我的岩友', style: Theme.of(context).textTheme.labelLarge),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: WanpanColors.inkSecondary,
          ),
        ],
      ),
    ),
  );
}

class _FeedEntry {
  _FeedEntry(this.post)
    : liked = post.liked,
      likeCount = post.likeCount,
      favorited = post.favorited;
  final FeedPost post;
  bool liked;
  bool favorited;
  int likeCount;
}

class _ScopePicker extends StatelessWidget {
  const _ScopePicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: WanpanColors.surfaceSoft,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      border: Border.all(color: WanpanColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ScopeButton(
            label: '广场',
            icon: Icons.public_rounded,
            selected: value == 'square',
            onTap: () => onChanged('square'),
          ),
        ),
        Expanded(
          child: _ScopeButton(
            label: '朋友圈',
            icon: Icons.people_alt_rounded,
            selected: value == 'friends',
            onTap: () => onChanged('friends'),
          ),
        ),
      ],
    ),
  );
}

class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WanpanPressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    pressedScale: .985,
    child: AnimatedContainer(
      duration: WanpanMotion.duration(context, WanpanMotion.exit),
      curve: WanpanMotion.curve(context),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? WanpanColors.surface : Colors.transparent,
        border: Border.all(
          color: selected ? WanpanColors.border : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: selected
            ? const [
                BoxShadow(color: WanpanColors.border, offset: Offset(0, 2)),
              ]
            : const [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? WanpanColors.coral : WanpanColors.muted,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? WanpanColors.ink : WanpanColors.muted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    super.key,
    required this.entry,
    required this.liking,
    required this.onLike,
    required this.onFavorite,
    required this.favoriting,
    required this.onOpen,
    this.onOpenUser,
    this.onDelete,
    this.deleting = false,
  });

  final _FeedEntry entry;
  final bool liking;
  final bool favoriting;
  final VoidCallback onFavorite;
  final VoidCallback onLike;
  final VoidCallback? onOpen;
  final VoidCallback? onOpenUser;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final post = entry.post;
    final nickname = post.user?.nickname ?? '岩友';
    return WanpanCard(
      onTap: onOpen,
      semanticLabel: '打开$nickname的动态',
      hasShadow: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenUser,
                child: _Avatar(url: post.user?.avatarUrl, label: nickname),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpenUser,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (post.gymName != null || post.grade != null)
                        Text(
                          [
                            post.gymName,
                            post.routeName,
                            post.grade,
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  tooltip: '动态操作',
                  enabled: !deleting,
                  onSelected: (_) => onDelete?.call(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除动态',
                        style: TextStyle(color: WanpanColors.danger),
                      ),
                    ),
                  ],
                )
              else
                IconButton(
                  tooltip: '更多',
                  onPressed: onOpen,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: WanpanColors.muted,
                  ),
                ),
            ],
          ),
          if ((post.caption ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.caption!,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w400, height: 1.45),
            ),
          ],
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ImageGrid(urls: post.imageUrls),
          ] else if (post.videoUrl != null) ...[
            const SizedBox(height: 10),
            WanpanVideoCover(url: post.videoUrl!),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LikeButton(
                liked: entry.liked,
                count: entry.likeCount,
                onTap: liking || deleting ? null : onLike,
              ),
              Semantics(
                label: '查看评论',
                onTap: onOpen,
                enabled: onOpen != null,
                value: '${post.commentCount}条评论',
                button: true,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 44,
                        minWidth: 44,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 22,
                            color: WanpanColors.inkSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${post.commentCount}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: entry.favorited ? '取消收藏' : '收藏',
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: favoriting || deleting ? null : onFavorite,
                icon: Icon(
                  entry.favorited
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                ),
                color: entry.favorited
                    ? WanpanColors.coral
                    : WanpanColors.inkSecondary,
              ),
              Text(
                _relativeTime(post.sentAt),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.count,
    required this.onTap,
  });
  final bool liked;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: liked ? '取消点赞' : '点赞',
      value: '$count个赞',
      onTap: onTap,
      enabled: onTap != null,
      button: true,
      toggled: liked,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(WanpanRadii.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: liked ? 1.08 : 1,
                  duration: WanpanMotion.duration(context, WanpanMotion.press),
                  curve: WanpanMotion.curve(context),
                  child: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 24,
                    color: liked
                        ? WanpanColors.coral
                        : WanpanColors.inkSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: WanpanMotion.duration(context, WanpanMotion.exit),
                  child: Text(
                    '$count',
                    key: ValueKey(count),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.api, required this.initialVisibility});
  final ApiClient api;
  final String initialVisibility;
  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  late final _repository = FeedRepository(widget.api);
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  late String _visibility = widget.initialVisibility;
  bool _submitting = false;
  double _progress = 0;
  String _stage = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      (_controller.text.trim().isNotEmpty || _images.isNotEmpty);

  Future<void> _pickImages() async {
    final remaining = 9 - _images.length;
    if (remaining <= 0 || _submitting) return;
    final picked = await _picker.pickMultiImage(
      imageQuality: 86,
      limit: remaining,
    );
    if (!mounted || picked.isEmpty) return;
    setState(() => _images.addAll(picked.take(remaining)));
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _progress = 0;
      _stage = _images.isEmpty ? '正在发布…' : '正在上传图片…';
    });
    try {
      final urls = <String>[];
      for (var index = 0; index < _images.length; index++) {
        final image = _images[index];
        urls.add(
          await widget.api.uploadFile(
            image.path,
            filename: image.name,
            onSendProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(() {
                _progress = (index + sent / total) / _images.length;
                _stage = '正在上传 ${index + 1}/${_images.length}';
              });
            },
          ),
        );
      }
      if (mounted) {
        setState(() {
          _progress = 1;
          _stage = '正在发布…';
        });
      }
      final published = await _repository.publishMoment(
        caption: text,
        imageUrls: urls,
        visibility: _visibility,
      );
      if (mounted) {
        Navigator.pop(context, (
          moderationStatus: published.moderationStatus,
          visibility: _visibility,
        ));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      WanpanNotice.show(context, '发布失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !_submitting,
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: WanpanMotion.duration(context, WanpanMotion.exit),
          padding: EdgeInsets.fromLTRB(20, 4, 20, keyboard + 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .82,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 82,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '分享攀岩动态',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        Positioned(
                          left: 134,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: WanpanColors.surfaceSoft,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              '记录每一次进步，\n也分享每一份快乐！',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 32,
                          top: -24,
                          width: 104,
                          height: 92,
                          child: Image.asset(
                            AppAssets.profilePeekCat,
                            cacheWidth: 360,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        Positioned(
                          right: -10,
                          top: 12,
                          child: IconButton(
                            tooltip: '关闭',
                            onPressed: _submitting
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 6,
                    maxLines: 8,
                    maxLength: 300,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      hintText: '今天在墙上发生了什么？',
                      fillColor: WanpanColors.surface,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _LocalImageGrid(
                      images: _images,
                      enabled: !_submitting,
                      onRemove: (index) =>
                          setState(() => _images.removeAt(index)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _submitting || _images.length >= 9
                          ? null
                          : _pickImages,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text('添加图片 ${_images.length}/9'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('谁可以看', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _visibility == 'public',
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() => _visibility = 'public'),
                        avatar: const Icon(Icons.public_rounded, size: 18),
                        label: const Text('广场'),
                      ),
                      ChoiceChip(
                        selected: _visibility == 'friends',
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() => _visibility = 'friends'),
                        avatar: const Icon(Icons.people_alt_rounded, size: 18),
                        label: const Text('仅岩友'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _visibility == 'public'
                        ? '发布后所有人都可在广场看到'
                        : '发布后仅你和已添加的岩友可见',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (_submitting) ...[
                    const SizedBox(height: 14),
                    Text(_stage, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _images.isEmpty || _progress == 0
                          ? null
                          : _progress,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ],
                  const SizedBox(height: 20),
                  WanpanButton(
                    label: '发布动态',
                    loading: _submitting,
                    onPressed: _canSubmit ? _submit : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalImageGrid extends StatelessWidget {
  const _LocalImageGrid({
    required this.images,
    required this.enabled,
    required this.onRemove,
  });

  final List<XFile> images;
  final bool enabled;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final rows = (images.length / 3).ceil();
    return SizedBox(
      height: rows * 96,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: images.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemBuilder: (context, index) => Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(images[index].path),
                fit: BoxFit.cover,
                cacheWidth: 720,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: const Color(0xB817191C),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? () => onRemove(index) : null,
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.urls});
  final List<String> urls;
  @override
  Widget build(BuildContext context) {
    final count = urls.length.clamp(1, 9);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count == 1 ? 1 : 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (_, index) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          urls[index],
          fit: BoxFit.cover,
          cacheWidth: count == 1 ? 1080 : 480,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: WanpanColors.surfaceSoft,
            child: Icon(Icons.broken_image_outlined, color: WanpanColors.muted),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.label});
  final String? url;
  final String label;
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: WanpanColors.coralSoft,
      backgroundImage: url == null
          ? null
          : ResizeImage.resizeIfNeeded(160, 160, NetworkImage(url!)),
      child: url == null
          ? Text(
              label.isEmpty ? '岩' : label.characters.first,
              style: const TextStyle(
                color: WanpanColors.coralStrong,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const WanpanMascot(
                  asset: AppAssets.mascotWelcome,
                  width: 172,
                  height: 164,
                  radius: 36,
                ),
                Positioned(
                  right: -4,
                  bottom: 4,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: WanpanColors.sunflower,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 23, color: WanpanColors.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime? time) {
  if (time == null) return '';
  final value = DateTime.now().difference(time.toLocal());
  if (value.inMinutes < 1) return '刚刚';
  if (value.inHours < 1) return '${value.inMinutes}分钟前';
  if (value.inDays < 1) return '${value.inHours}小时前';
  if (value.inDays < 7) return '${value.inDays}天前';
  return '${time.month}月${time.day}日';
}
