import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/feed_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/feed_repository.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../auth/application/session_controller.dart';
import '../../shared/motion/wanpan_motion.dart';

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
  final Set<String> _likingPostIds = {};
  String _scope = 'square';
  bool _loading = true;
  String? _error;
  int _loadRevision = 0;

  List<_FeedEntry> get _items => _scopeCache[_scope] ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = false}) async {
    final scope = _scope;
    final revision = ++_loadRevision;
    if (!widget.session.isAuthenticated) {
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
          .map(_FeedEntry.new)
          .toList();
      if (!mounted || revision != _loadRevision || scope != _scope) return;
      setState(() {
        _scopeCache[scope] = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _loadRevision || scope != _scope) return;
      setState(() {
        _loading = false;
        _error = '广场暂时走丢了，稍后再试';
      });
      if (_items.isNotEmpty) _notice('刷新失败，仍为你保留上次内容');
    }
  }

  Future<void> _toggleLike(_FeedEntry entry) async {
    final postId = entry.post.id;
    if (_likingPostIds.contains(postId)) return;
    final previous = entry.liked;
    final copies = [
      for (final items in _scopeCache.values)
        for (final item in items)
          if (item.post.id == postId)
            (entry: item, liked: item.liked, likeCount: item.likeCount),
    ];
    setState(() {
      _likingPostIds.add(postId);
      for (final copy in copies) {
        copy.entry.liked = !previous;
        copy.entry.likeCount = (copy.entry.likeCount + (previous ? -1 : 1))
            .clamp(0, 1 << 31);
      }
    });
    try {
      if (previous) {
        await widget.api.deleteJson('/sends/$postId/like');
      } else {
        await widget.api.postJson('/sends/$postId/like');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final copy in copies) {
          copy.entry.liked = copy.liked;
          copy.entry.likeCount = copy.likeCount;
        }
      });
      _notice('操作没有保存，请重试');
    } finally {
      if (mounted) setState(() => _likingPostIds.remove(postId));
    }
  }

  Future<void> _compose() async {
    if (!widget.session.isAuthenticated) {
      _notice('登录后就可以分享攀岩动态');
      return;
    }
    final published = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _ComposeSheet(
        api: widget.api,
        initialVisibility: _scope == 'square' ? 'public' : 'friends',
      ),
    );
    if (published == true && mounted) {
      _notice('已提交审核，通过后会出现在对应动态里');
      await _load();
    }
  }

  Future<void> _openFriends() async {
    await context.push('/friends');
    if (!mounted) return;
    setState(() => _scopeCache.remove('friends'));
    await _load();
  }

  Future<void> _openPost(String postId) async {
    await context.push('/posts/$postId');
    if (mounted) await _load();
  }

  Future<void> _openUser(String userId) async {
    await context.push('/users/$userId');
    if (!mounted) return;
    setState(() => _scopeCache.remove('friends'));
    await _load();
  }

  void _changeScope(String value) {
    if (value == _scope) return;
    setState(() {
      _scope = value;
      _loading = !_scopeCache.containsKey(value);
      _error = null;
    });
    _load();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('广场'),
        actions: [
          IconButton(
            tooltip: '我的岩友',
            onPressed: _openFriends,
            icon: const Icon(Icons.people_outline_rounded),
          ),
          IconButton(
            tooltip: '发布动态',
            onPressed: _compose,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: _ScopePicker(value: _scope, onChanged: _changeScope),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              child: _body(),
            ),
          ),
        ],
      ),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.small(
              onPressed: _compose,
              tooltip: '发布动态',
              child: const Icon(Icons.edit_rounded),
            ),
    );
  }

  Widget _body() {
    if (!widget.session.isAuthenticated) {
      return const _FeedEmpty(
        key: ValueKey('signed-out'),
        icon: Icons.people_alt_outlined,
        title: '登录后看看岩友们在爬什么',
        description: '点赞、评论，也可以分享自己的完攀瞬间。',
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = _items[index];
          return _PostCard(
            key: ValueKey(entry.post.id),
            entry: entry,
            onLike: () => _toggleLike(entry),
            liking: _likingPostIds.contains(entry.post.id),
            onOpen: () => _openPost(entry.post.id),
            onOpenUser: entry.post.user == null
                ? null
                : () => _openUser(entry.post.user!.id),
          );
        },
      ),
    );
  }
}

class _FeedEntry {
  _FeedEntry(this.post) : liked = post.liked, likeCount = post.likeCount;
  final FeedPost post;
  bool liked;
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? WanpanColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x1217191C),
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
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
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? WanpanColors.ink : WanpanColors.muted,
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
    required this.onOpen,
    this.onOpenUser,
  });

  final _FeedEntry entry;
  final bool liking;
  final VoidCallback onLike;
  final VoidCallback onOpen;
  final VoidCallback? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final post = entry.post;
    final nickname = post.user?.nickname ?? '岩友';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                ],
              ),
              if ((post.caption ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  post.caption!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (post.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ImageGrid(urls: post.imageUrls),
              ] else if (post.videoUrl != null) ...[
                const SizedBox(height: 14),
                Container(
                  height: 176,
                  decoration: BoxDecoration(
                    color: WanpanColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(WanpanRadii.medium),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 52,
                          color: WanpanColors.coral,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '点击查看完攀视频',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _LikeButton(
                    liked: entry.liked,
                    count: entry.likeCount,
                    onTap: liking ? null : onLike,
                  ),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 20,
                    color: WanpanColors.inkSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${post.commentCount}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    _relativeTime(post.sentAt),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: liked ? 1.08 : 1,
              duration: WanpanMotion.duration(context, WanpanMotion.press),
              curve: WanpanMotion.curve(context),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 21,
                color: liked ? WanpanColors.coral : WanpanColors.inkSecondary,
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
          _stage = '正在提交审核…';
        });
      }
      await widget.api.postJson(
        '/sends/moments',
        data: {'caption': text, 'imageUrls': urls, 'visibility': _visibility},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发布失败，请稍后重试')));
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '分享攀岩动态',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: 300,
                    enabled: !_submitting,
                    decoration: const InputDecoration(hintText: '今天在墙上发生了什么？'),
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
                        ? '通过审核后所有人都可在广场看到'
                        : '通过审核后仅你和已添加的岩友可见',
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
                    label: '提交发布',
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
              child: Image.file(File(images[index].path), fit: BoxFit.cover),
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
      backgroundImage: url == null ? null : NetworkImage(url!),
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
            Icon(icon, size: 54, color: WanpanColors.coral),
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
