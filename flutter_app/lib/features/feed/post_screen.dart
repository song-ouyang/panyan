import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/network/api_client.dart';
import '../auth/application/session_controller.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_video_player.dart';

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
  FeedPost? _post;
  bool _loading = true;
  bool _commenting = false;
  bool _liked = false;
  int _likeCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final post = FeedPost.fromJson(
        await widget.api.getJson('/sends/${widget.postId}'),
      );
      if (!mounted) return;
      setState(() {
        _post = post;
        _liked = post.liked;
        _likeCount = post.likeCount;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '这条动态暂时无法打开';
      });
    }
  }

  Future<void> _openUser(String userId) async {
    await context.push('/users/$userId');
    if (mounted) await _load();
  }

  Future<void> _toggleLike() async {
    if (!widget.session.isAuthenticated) return _notice('登录后才能点赞');
    final previous = _liked;
    setState(() {
      _liked = !previous;
      _likeCount += previous ? -1 : 1;
    });
    try {
      if (previous) {
        await widget.api.deleteJson('/sends/${widget.postId}/like');
      } else {
        await widget.api.postJson('/sends/${widget.postId}/like');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = previous;
        _likeCount += previous ? 1 : -1;
      });
      _notice('点赞没有保存，请重试');
    }
  }

  Future<void> _comment() async {
    final content = _commentController.text.trim();
    if (!widget.session.isAuthenticated) return _notice('登录后才能评论');
    if (content.isEmpty || _commenting) return;
    setState(() => _commenting = true);
    try {
      await widget.api.postJson(
        '/sends/${widget.postId}/comments',
        data: {'content': content},
      );
      _commentController.clear();
      if (mounted) _notice('评论已提交');
      await _load();
    } catch (_) {
      if (mounted) _notice('评论失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _commenting = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('动态详情')),
      body: AnimatedSwitcher(
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
    final post = _post!;
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
                onTap: _toggleLike,
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
            ],
          ),
          const Divider(height: 36),
          Text(
            '评论 ${post.comments.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (post.comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '还没有评论，来聊聊这条线路吧。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            ...post.comments.map((comment) => _CommentTile(comment: comment)),
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
  const _CommentTile({required this.comment});
  final FeedComment comment;
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
