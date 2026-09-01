import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/user_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_pressable.dart';

typedef OpenFriendProfile = Future<Object?> Function(String userId);

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({required this.api, super.key, this.onOpenProfile});

  final ApiClient api;
  final OpenFriendProfile? onOpenProfile;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final ProfileRepository _repository = ProfileRepository(widget.api);
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final Set<String> _busyUsers = {};
  Timer? _searchDebounce;
  List<UserSummary> _friends = const [];
  List<UserSummary> _requests = const [];
  List<UserSummary> _searchResults = const [];
  bool _loading = true;
  bool _searching = false;
  String? _error;
  int _searchRevision = 0;
  int _socialRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadSocial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSocial({bool showLoading = true}) async {
    final revision = ++_socialRevision;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await Future.wait([
        _repository.getFriends(),
        _repository.getFriendRequests(),
      ]);
      if (!mounted || revision != _socialRevision) return;
      setState(() {
        _friends = result[0];
        _requests = result[1];
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || revision != _socialRevision) return;
      setState(() {
        _loading = false;
        _error = '岩友列表暂时没有加载出来';
      });
    }
  }

  Future<void> _refresh() async {
    await _loadSocial(showLoading: false);
    if (_searchController.text.trim().isNotEmpty) await _searchNow();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final revision = ++_searchRevision;
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      () => _search(query, revision),
    );
  }

  Future<void> _searchNow() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final revision = ++_searchRevision;
    setState(() => _searching = true);
    await _search(query, revision);
  }

  Future<void> _search(String query, int revision) async {
    try {
      final results = await _repository.searchUsers(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      _notice('没有搜索到，稍后再试一次');
    }
  }

  Future<void> _openProfile(String userId) async {
    final openProfile = widget.onOpenProfile;
    if (openProfile == null) return;
    await openProfile(userId);
    if (mounted) await _refresh();
  }

  Future<void> _actOnSearchResult(UserSummary user) async {
    final friendship = user.friendship ?? 'none';
    if (friendship == 'sent' || friendship == 'accepted') return;
    _setBusy(user.id, true);
    try {
      final next = friendship == 'received'
          ? await _repository.acceptFriendRequest(user.id)
          : await _repository.sendFriendRequest(user.id);
      if (!mounted) return;
      _replaceSearchUser(_withFriendship(user, next));
      if (next == 'accepted') {
        setState(() => _requests = _withoutUser(_requests, user.id));
        await _loadSocial(showLoading: false);
      }
      _notice(next == 'accepted' ? '已经成为岩友啦' : '岩友申请已发送');
    } catch (_) {
      if (mounted) _notice('操作没有保存，请稍后重试');
    } finally {
      _setBusy(user.id, false);
    }
  }

  Future<void> _accept(UserSummary user) async {
    _setBusy(user.id, true);
    try {
      await _repository.acceptFriendRequest(user.id);
      if (!mounted) return;
      setState(() => _requests = _withoutUser(_requests, user.id));
      _replaceSearchUser(_withFriendship(user, 'accepted'));
      await _loadSocial(showLoading: false);
      if (mounted) _notice('已经成为岩友啦');
    } catch (_) {
      if (mounted) _notice('接受失败，请稍后重试');
    } finally {
      _setBusy(user.id, false);
    }
  }

  Future<void> _remove(UserSummary user) async {
    final confirmed = await _confirmRemove(user.nickname);
    if (confirmed != true || !mounted) return;
    _setBusy(user.id, true);
    try {
      await _repository.removeFriend(user.id);
      if (!mounted) return;
      setState(() => _friends = _withoutUser(_friends, user.id));
      _replaceSearchUser(_withFriendship(user, 'none'));
      _notice('已解除岩友关系');
    } catch (_) {
      if (mounted) _notice('没有删除成功，请稍后重试');
    } finally {
      _setBusy(user.id, false);
    }
  }

  Future<bool?> _confirmRemove(String nickname) => showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '不再和 $nickname 做岩友？',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '解除后，你们仅对岩友可见的动态将不再互相展示。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _SheetButton(
              label: '解除岩友',
              foreground: WanpanColors.danger,
              background: const Color(0xFFFFF1EF),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            _SheetButton(
              label: '先不解除',
              foreground: WanpanColors.ink,
              background: WanpanColors.surfaceSoft,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );

  void _replaceSearchUser(UserSummary replacement) {
    if (!mounted) return;
    setState(() {
      _searchResults = [
        for (final user in _searchResults)
          if (user.id == replacement.id) replacement else user,
      ];
    });
  }

  void _setBusy(String userId, bool busy) {
    if (!mounted) return;
    setState(() {
      if (busy) {
        _busyUsers.add(userId);
      } else {
        _busyUsers.remove(userId);
      }
    });
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: const Text(
          '我的岩友',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            _SearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              searching: _searching,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _searchNow(),
            ),
            AnimatedSwitcher(
              duration: WanpanMotion.duration(context, WanpanMotion.exit),
              child: _searchController.text.trim().isEmpty
                  ? const SizedBox.shrink(key: ValueKey('search-hidden'))
                  : Padding(
                      key: const ValueKey('search-results'),
                      padding: const EdgeInsets.only(top: 18),
                      child: _SearchSection(
                        query: _searchController.text.trim(),
                        users: _searchResults,
                        searching: _searching,
                        busyUsers: _busyUsers,
                        onAction: _actOnSearchResult,
                        onOpenProfile: widget.onOpenProfile == null
                            ? null
                            : _openProfile,
                      ),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _InlineError(message: _error!, onRetry: _loadSocial),
            ],
            if (_loading) ...[
              const SizedBox(height: 56),
              const Center(child: CircularProgressIndicator(strokeWidth: 3)),
            ] else ...[
              if (_requests.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionTitle(title: '新的岩友', count: _requests.length),
                const SizedBox(height: 10),
                WanpanCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _requests.length; i++) ...[
                        if (i > 0) const Divider(),
                        _UserRow(
                          user: _requests[i],
                          onTap: widget.onOpenProfile == null
                              ? null
                              : () => _openProfile(_requests[i].id),
                          trailing: _CompactAction(
                            label: '接受',
                            busy: _busyUsers.contains(_requests[i].id),
                            onTap: () => _accept(_requests[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _SectionTitle(title: '全部岩友', count: _friends.length),
              const SizedBox(height: 10),
              if (_friends.isEmpty)
                _FriendsEmpty(
                  onSearch: () {
                    _searchFocusNode.requestFocus();
                    Scrollable.ensureVisible(
                      _searchFocusNode.context ?? context,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                    );
                  },
                )
              else
                WanpanCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _friends.length; i++) ...[
                        if (i > 0) const Divider(),
                        _UserRow(
                          user: _friends[i],
                          onTap: widget.onOpenProfile == null
                              ? null
                              : () => _openProfile(_friends[i].id),
                          trailing: _RemoveButton(
                            busy: _busyUsers.contains(_friends[i].id),
                            onTap: () => _remove(_friends[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: '搜索昵称，找到新岩友',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.cancel_rounded),
              ),
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.query,
    required this.users,
    required this.searching,
    required this.busyUsers,
    required this.onAction,
    required this.onOpenProfile,
  });

  final String query;
  final List<UserSummary> users;
  final bool searching;
  final Set<String> busyUsers;
  final ValueChanged<UserSummary> onAction;
  final ValueChanged<String>? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: '搜索结果', count: users.length),
        const SizedBox(height: 10),
        if (!searching && users.isEmpty)
          WanpanCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.person_search_rounded,
                  color: WanpanColors.coral,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '没有找到“$query”，换个昵称试试。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else if (users.isNotEmpty)
          WanpanCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < users.length; i++) ...[
                  if (i > 0) const Divider(),
                  _UserRow(
                    user: users[i],
                    showBio: true,
                    onTap: onOpenProfile == null
                        ? null
                        : () => onOpenProfile!(users[i].id),
                    trailing: _SearchAction(
                      friendship: users[i].friendship ?? 'none',
                      busy: busyUsers.contains(users[i].id),
                      onTap: () => onAction(users[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.trailing,
    this.onTap,
    this.showBio = false,
  });

  final UserSummary user;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool showBio;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (showBio) ...[
                  const SizedBox(height: 2),
                  Text(
                    user.bio?.trim().isNotEmpty == true
                        ? user.bio!
                        : '正在寻找下一条线路',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
    if (onTap == null) return content;
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: '查看${user.nickname}的主页',
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      child: content,
    );
  }
}

class _SearchAction extends StatelessWidget {
  const _SearchAction({
    required this.friendship,
    required this.busy,
    required this.onTap,
  });

  final String friendship;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (friendship) {
      'sent' => '待确认',
      'received' => '接受',
      'accepted' => '已是岩友',
      'blocked' => '无法添加',
      _ => '加岩友',
    };
    final active = friendship == 'none' || friendship == 'received';
    return _CompactAction(
      label: label,
      busy: busy,
      muted: !active,
      onTap: active ? onTap : null,
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.label,
    required this.busy,
    this.onTap,
    this.muted = false,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final child = AnimatedContainer(
      duration: WanpanMotion.duration(context, WanpanMotion.press),
      curve: WanpanMotion.curve(context),
      constraints: const BoxConstraints(minWidth: 72, minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? WanpanColors.surfaceSoft : WanpanColors.coral,
        borderRadius: BorderRadius.circular(WanpanRadii.pill),
      ),
      child: busy
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: muted ? WanpanColors.muted : Colors.white,
              ),
            )
          : Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: muted ? WanpanColors.inkSecondary : Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
    if (!enabled) return child;
    return WanpanPressable(
      onTap: onTap,
      enableHaptics: true,
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
      child: child,
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.square(
      dimension: 42,
      child: Center(
        child: busy
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.more_horiz_rounded, color: WanpanColors.muted),
      ),
    );
    if (busy) return child;
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: '管理岩友',
      enableHaptics: true,
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
      child: child,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final UserSummary user;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 23,
      backgroundColor: WanpanColors.coralSoft,
      backgroundImage: user.avatarUrl == null
          ? null
          : NetworkImage(user.avatarUrl!),
      child: user.avatarUrl == null
          ? Text(
              user.nickname.isEmpty ? '岩' : user.nickname.characters.first,
              style: const TextStyle(
                color: WanpanColors.coralStrong,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 20),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: WanpanColors.coralSoft,
            borderRadius: BorderRadius.circular(WanpanRadii.pill),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: WanpanColors.coralStrong,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _FriendsEmpty extends StatelessWidget {
  const _FriendsEmpty({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 26),
        SizedBox(
          width: 330,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _FriendTrailPainter()),
              ),
              Image.asset(
                AppAssets.friendsEmptyCat,
                width: 300,
                height: 286,
                fit: BoxFit.contain,
                cacheWidth: 720,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => Image.asset(
                  AppAssets.mascotWelcome,
                  width: 300,
                  height: 286,
                  fit: BoxFit.contain,
                  cacheWidth: 720,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '还没有岩友',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 30, letterSpacing: -.7),
        ),
        const SizedBox(height: 10),
        Text(
          '搜索昵称，认识下一位一起上墙的伙伴',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: WanpanColors.inkSecondary, fontSize: 15),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: 220,
          child: WanpanButton(label: '搜索岩友', onPressed: onSearch),
        ),
      ],
    );
  }
}

class _FriendTrailPainter extends CustomPainter {
  const _FriendTrailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final trail = Paint()
      ..color = WanpanColors.border.withValues(alpha: .58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * .14, size.height * .74)
      ..cubicTo(
        size.width * .02,
        size.height * .57,
        size.width * .24,
        size.height * .43,
        size.width * .18,
        size.height * .27,
      )
      ..cubicTo(
        size.width * .28,
        size.height * .11,
        size.width * .43,
        size.height * .16,
        size.width * .39,
        size.height * .30,
      );
    canvas.drawPath(path, trail);
    final dot = Paint();
    for (final entry in <(Offset, Color)>[
      (Offset(size.width * .08, size.height * .37), WanpanColors.mint),
      (Offset(size.width * .86, size.height * .67), WanpanColors.sky),
      (Offset(size.width * .90, size.height * .84), WanpanColors.coral),
      (Offset(size.width * .72, size.height * .21), WanpanColors.sunflower),
    ]) {
      dot.color = entry.$2.withValues(alpha: .78);
      canvas.drawCircle(entry.$1, 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return WanpanCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: WanpanColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      onTap: onTap,
      enableHaptics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

List<UserSummary> _withoutUser(List<UserSummary> users, String userId) =>
    users.where((user) => user.id != userId).toList(growable: false);

UserSummary _withFriendship(UserSummary user, String friendship) => UserSummary(
  id: user.id,
  nickname: user.nickname,
  avatarUrl: user.avatarUrl,
  bio: user.bio,
  role: user.role,
  friendship: friendship,
  createdAt: user.createdAt,
);
