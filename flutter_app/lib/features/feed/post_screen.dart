import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/repositories/feed_repository.dart';
import '../auth/application/session_controller.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_content_safety.dart';
import '../../shared/widgets/wanpan_notice.dart';
import '../../shared/widgets/wanpan_video_player.dart';

enum _PostSafetyAction { report, block }

enum _CommentSafetyAction { report, block }

class PostScreen extends StatefulWidget {
  const PostScreen({
    super.key,
    required this.api,
    required this.session,
    required this.postId,
  });

  final ApiClient api;
  final SessionController session;
  final String postId;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _commentController = TextEditingController();
  late final FeedRepository _repository = FeedRepository(widget.api);
  FeedPost? _post;
  List<FeedComment> _comments = const [];
  int _loadRevision = 0;
  String? _sessionToken;
  bool _loading = true;
  bool _commenting = false;
  bool _safetySubmitting = false;
  bool _deletingPost = false;
  bool _postDeleted = false;
  bool _liked = false;
  bool _liking = false;
  bool _favorited = false;
  bool _favoriting = false;
  int _likeCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionToken = widget.session.token;
    widget.session.addListener(_handleSessionChanged);
    widget.api.socialActivity.addListener(_handleSocialChanged);
    _load();
  }

  void _handleSocialChanged() {
    final change = widget.api.socialActivity;
    if (!mounted ||
        _postDeleted ||
        (change.changedPostId != null &&
            change.changedPostId != widget.postId)) {
      return;
    }
    if (change.changedPostId == widget.postId &&
        change.postDeleted &&
        !_deletingPost) {
      ++_loadRevision;
      setState(() {
        _postDeleted = true;
        _post = null;
        _comments = const [];
        _loading = false;
        _error = '这条动态已删除';
      });
      return;
    }
    if (change.changedPostId != null &&
        (_liking || _favoriting || _commenting || _deletingPost)) {
      return;
    }
    if (change.changedPostId == null) {
      setState(() {
        _post = null;
        _comments = const [];
        _loading = true;
      });
    }
    unawaited(_load());
  }

  void _handleSessionChanged() {
    final token = widget.session.token;
    if (token == _sessionToken) return;
    _sessionToken = token;
    ++_loadRevision;
    setState(() {
      _post = null;
      _comments = const [];
      _loading = true;
      _commenting = false;
      _liking = false;
      _favoriting = false;
      _liked = false;
      _favorited = false;
      _deletingPost = false;
      _error = null;
    });
    _commentController.clear();
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    widget.api.socialActivity.removeListener(_handleSocialChanged);
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load({bool afterComment = false}) async {
    if (_postDeleted) return;
    final revision = ++_loadRevision;
    final token = widget.session.token;
    try {
      final post = await _repository.getPost(widget.postId);
      if (!mounted ||
          _postDeleted ||
          revision != _loadRevision ||
          token != widget.session.token) {
        return;
      }
      setState(() {
        _post = post;
        _comments = post.comments;
        if (!_liking) {
          _liked = post.liked;
          _likeCount = post.likeCount;
        }
        if (!_favoriting) _favorited = post.favorited;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted ||
          _postDeleted ||
          revision != _loadRevision ||
          token != widget.session.token) {
        return;
      }
      final unavailable =
          error is ApiException && [401, 403, 404].contains(error.statusCode);
      final preserveContent = _post != null && !unavailable;
      setState(() {
        _loading = false;
        _error = preserveContent ? null : '这条动态暂时无法打开';
        if (unavailable) {
          _post = null;
          _comments = const [];
        }
      });
      if (preserveContent) {
        _notice(afterComment ? '评论已提交，暂时无法刷新动态' : '刷新失败，仍保留当前内容');
      }
    }
  }

  Future<void> _openUser(String userId) async {
    await context.push('/users/$userId');
    if (mounted) await _load();
  }

  Future<void> _toggleLike() => _toggleReaction(favorite: false);

  Future<void> _toggleFavorite() => _toggleReaction(favorite: true);

  Future<void> _toggleReaction({required bool favorite}) async {
    if (_deletingPost ||
        _postDeleted ||
        _post == null ||
        (favorite ? _favoriting : _liking)) {
      return;
    }
    if (!_requireAuthentication()) return;
    final token = widget.session.token;
    final previous = favorite ? _favorited : _liked;
    final previousCount = _likeCount;
    ++_loadRevision;
    setState(() {
      if (favorite) {
        _favoriting = true;
        _favorited = !previous;
      } else {
        _liking = true;
        _liked = !previous;
        _likeCount = (_likeCount + (previous ? -1 : 1)).clamp(0, 1 << 31);
      }
    });
    try {
      if (favorite) {
        await _repository.setFavorited(widget.postId, favorited: !previous);
      } else {
        await _repository.setLiked(widget.postId, liked: !previous);
      }
    } catch (_) {
      if (!mounted || _postDeleted || token != widget.session.token) return;
      setState(() {
        if (favorite) {
          _favorited = previous;
        } else {
          _liked = previous;
          _likeCount = previousCount;
        }
      });
      _notice(favorite ? '收藏没有保存，请重试' : '点赞没有保存，请重试');
    } finally {
      if (mounted && !_postDeleted && token == widget.session.token) {
        ++_loadRevision;
        setState(() {
          if (favorite) {
            _favoriting = false;
          } else {
            _liking = false;
          }
        });
        unawaited(_load());
      }
    }
  }

  Future<void> _comment() async {
    if (_deletingPost || _postDeleted) return;
    if (!_requireAuthentication()) return;
    final content = _commentController.text.trim();
    if (content.isEmpty || _commenting) return;
    final token = widget.session.token;
    final author = widget.session.user;
    setState(() => _commenting = true);
    try {
      final comment = await _repository.addComment(
        widget.postId,
        content,
        author: author,
      );
      if (!mounted || _postDeleted || token != widget.session.token) return;
      setState(() {
        // Ignore older detail requests that began before this comment saved.
        ++_loadRevision;
        _comments = [
          ..._comments.where((item) => item.id != comment.id),
          comment,
        ];
      });
      if (_commentController.text.trim() == content) _commentController.clear();
      _notice(comment.isPending ? '评论已提交，审核后其他岩友可见' : '评论已提交');
      await _load(afterComment: true);
    } catch (_) {
      if (mounted && !_postDeleted && token == widget.session.token) {
        _notice('评论失败，请稍后重试');
      }
    } finally {
      if (mounted && !_postDeleted && token == widget.session.token) {
        setState(() => _commenting = false);
      }
    }
  }

  bool _requireAuthentication() {
    if (widget.session.isAuthenticated) return true;
    final returnTo = Uri(pathSegments: ['', 'posts', widget.postId]).toString();
    context.push(
      Uri(path: '/login', queryParameters: {'from': returnTo}).toString(),
    );
    return false;
  }

  bool get _canActOnPost {
    final authorId = _post?.user?.id;
    return widget.session.isAuthenticated &&
        authorId != null &&
        authorId != widget.session.user?.id;
  }

  bool get _ownsPost =>
      widget.session.isAuthenticated &&
      _post?.user?.id != null &&
      _post!.user!.id == widget.session.user?.id;

  Future<void> _deletePost() async {
    if (!_ownsPost || _deletingPost || _safetySubmitting) return;
    final token = widget.session.token;
    final isCheckin = _post!.routeId != null;
    setState(() => _deletingPost = true);
    try {
      final confirmed = await showWanpanDeletePostConfirmation(
        context,
        isCheckin: isCheckin,
      );
      if (!confirmed ||
          !mounted ||
          token != widget.session.token ||
          !_ownsPost) {
        return;
      }
      await _repository.deletePost(widget.postId);
      if (!mounted || token != widget.session.token) return;
      ++_loadRevision;
      setState(() {
        _postDeleted = true;
        _post = null;
        _comments = const [];
      });
      _notice('动态已删除');
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/feed');
      }
    } catch (_) {
      if (mounted && token == widget.session.token) {
        _notice('删除失败，动态仍保留，请稍后重试');
      }
    } finally {
      if (mounted && !_postDeleted) setState(() => _deletingPost = false);
    }
  }

  Future<void> _handlePostSafetyAction(_PostSafetyAction action) async {
    if (_safetySubmitting || !_canActOnPost) return;
    switch (action) {
      case _PostSafetyAction.report:
        await _report(
          targetType: 'send',
          targetId: widget.postId,
          subject: '动态',
        );
      case _PostSafetyAction.block:
        final author = _post?.user;
        if (author == null) return;
        await _blockUser(author);
    }
  }

  Future<void> _report({
    required String targetType,
    required String targetId,
    required String subject,
  }) async {
    final reason = await showWanpanReportReasonSheet(context, subject: subject);
    if (reason == null || !mounted) return;
    setState(() => _safetySubmitting = true);
    try {
      await _repository.report(
        targetType: targetType,
        targetId: targetId,
        reason: reason,
      );
      if (mounted) _notice('举报已提交，我们会尽快处理');
    } catch (_) {
      if (mounted) _notice('举报没有提交成功，请稍后重试');
    } finally {
      if (mounted) setState(() => _safetySubmitting = false);
    }
  }

  Future<void> _blockUser(UserSummary user) async {
    if (user.id == widget.session.user?.id) return;
    final confirmed = await showWanpanBlockConfirmation(
      context,
      nickname: user.nickname,
    );
    if (!confirmed || !mounted) return;
    setState(() => _safetySubmitting = true);
    try {
      await _repository.blockUser(user.id);
      if (mounted) context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _safetySubmitting = false);
        _notice('拉黑没有保存，请稍后重试');
      }
    }
  }

  void _notice(String message) => WanpanNotice.show(context, message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: [
          if (_ownsPost)
            PopupMenuButton<String>(
              tooltip: '动态操作',
              enabled: !_deletingPost && !_safetySubmitting,
              onSelected: (_) => _deletePost(),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: WanpanColors.danger,
                    ),
                    title: Text(
                      '删除动态',
                      style: TextStyle(color: WanpanColors.danger),
                    ),
                  ),
                ),
              ],
            ),
          if (_canActOnPost)
            PopupMenuButton<_PostSafetyAction>(
              tooltip: '动态安全操作',
              enabled: !_safetySubmitting,
              onSelected: _handlePostSafetyAction,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PostSafetyAction.report,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined),
                    title: Text('举报动态'),
                  ),
                ),
                PopupMenuItem(
                  value: _PostSafetyAction.block,
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
        // Private pending comments must disappear immediately on account change.
        key: ValueKey(
          widget.session.isAuthenticated ? widget.session.user?.id : null,
        ),
        duration: WanpanMotion.duration(context, WanpanMotion.exit),
        child: _buildBody(),
      ),
      bottomNavigationBar: _post == null ? null : _commentBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
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
              size: 48,
              color: WanpanColors.muted,
            ),
            const SizedBox(height: 12),
            Text(_error!, style: Theme.of(context).textTheme.titleMedium),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final post = _post;
    if (post == null) return const SizedBox.shrink(key: ValueKey('removed'));
    final nickname = post.user?.nickname ?? '岩友';
    final avatarUrl = post.user?.avatarUrl;
    return RefreshIndicator(
      key: ValueKey(post.id),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          InkWell(
            onTap: post.user == null ? null : () => _openUser(post.user!.id),
            borderRadius: BorderRadius.circular(WanpanRadii.medium),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: WanpanColors.coralSoft,
                    backgroundImage: avatarUrl == null
                        ? null
                        : NetworkImage(avatarUrl),
                    child: avatarUrl == null
                        ? Text(
                            nickname.characters.first,
                            style: const TextStyle(
                              color: WanpanColors.coralStrong,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          [
                            post.gymName,
                            post.grade,
                          ].whereType<String>().join(' · '),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  if (post.user != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: WanpanColors.muted,
                    ),
                ],
              ),
            ),
          ),
          if ((post.caption ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(post.caption!, style: Theme.of(context).textTheme.bodyLarge),
          ],
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...post.imageUrls.map(
              (url) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WanpanRadii.medium),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 180,
                      child: ColoredBox(color: WanpanColors.surfaceSoft),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (post.videoUrl != null) ...[
            const SizedBox(height: 16),
            WanpanVideoPlayer(url: post.videoUrl!),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              InkWell(
                onTap: _liking || _deletingPost ? null : _toggleLike,
                borderRadius: BorderRadius.circular(WanpanRadii.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      AnimatedScale(
                        scale: _liked ? 1.1 : 1,
                        duration: WanpanMotion.duration(
                          context,
                          WanpanMotion.press,
                        ),
                        child: Icon(
                          _liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _liked
                              ? WanpanColors.coral
                              : WanpanColors.inkSecondary,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$_likeCount',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              TextButton.icon(
                onPressed: _favoriting || _deletingPost
                    ? null
                    : _toggleFavorite,
                icon: Icon(
                  _favorited ? Icons.star_rounded : Icons.star_border_rounded,
                ),
                label: Text(_favorited ? '已收藏' : '收藏'),
                style: TextButton.styleFrom(
                  foregroundColor: _favorited
                      ? WanpanColors.coral
                      : WanpanColors.inkSecondary,
                ),
              ),
            ],
          ),
          const Divider(height: 36),
          Text(
            '评论 ${_comments.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '还没有评论，来聊聊这条线路吧。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            ..._comments.map(
              (comment) => _CommentTile(
                comment: comment,
                onReport: comment.user.id == widget.session.user?.id
                    ? null
                    : () => _report(
                        targetType: 'comment',
                        targetId: comment.id,
                        subject: '评论',
                      ),
                onBlock: comment.user.id == widget.session.user?.id
                    ? null
                    : () => _blockUser(comment.user),
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        decoration: const BoxDecoration(
          color: WanpanColors.surface,
          border: Border(top: BorderSide(color: WanpanColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: '写评论…',
                  counterText: '',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _comment(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _commentController.text.trim().isEmpty || _commenting
                  ? null
                  : _comment,
              icon: _commenting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.onReport, this.onBlock});

  final FeedComment comment;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: WanpanColors.surfaceSoft,
            backgroundImage: comment.user.avatarUrl == null
                ? null
                : NetworkImage(comment.user.avatarUrl!),
            child: comment.user.avatarUrl == null
                ? const Icon(Icons.person_rounded, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.user.nickname,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (comment.isPending) ...[
                  const SizedBox(height: 5),
                  Text(
                    '审核中 · 仅自己可见',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: WanpanColors.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (onReport != null || onBlock != null)
            PopupMenuButton<_CommentSafetyAction>(
              tooltip: '评论安全操作',
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: WanpanColors.muted,
              ),
              onSelected: (action) {
                switch (action) {
                  case _CommentSafetyAction.report:
                    onReport?.call();
                  case _CommentSafetyAction.block:
                    onBlock?.call();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _CommentSafetyAction.report,
                  child: Text('举报评论'),
                ),
                PopupMenuItem(
                  value: _CommentSafetyAction.block,
                  child: Text(
                    '拉黑该用户',
                    style: TextStyle(color: WanpanColors.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
