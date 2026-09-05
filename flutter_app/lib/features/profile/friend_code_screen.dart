import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/user_models.dart';
import '../../core/services/share_service.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_pressable.dart';

class FriendCodeScreen extends StatefulWidget {
  const FriendCodeScreen({
    super.key,
    required this.user,
    required this.friendUrl,
    this.onScan,
    this.service = const ShareService(),
  });

  final UserSummary user;
  final Uri friendUrl;
  final Future<void> Function()? onScan;
  final ShareService service;

  @override
  State<FriendCodeScreen> createState() => _FriendCodeScreenState();
}

enum _FriendCodeAction { scan, copy }

class _FriendCodeScreenState extends State<FriendCodeScreen> {
  _FriendCodeAction? _activeAction;
  String? _feedback;
  bool _hasError = false;

  Future<void> _perform(_FriendCodeAction action) async {
    if (_activeAction != null) return;
    setState(() {
      _activeAction = action;
      _feedback = null;
      _hasError = false;
    });
    try {
      switch (action) {
        case _FriendCodeAction.scan:
          await widget.onScan?.call();
        case _FriendCodeAction.copy:
          await widget.service.copy(widget.friendUrl);
          if (mounted) {
            setState(() => _feedback = '好友链接已复制');
          }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _feedback = switch (action) {
          _FriendCodeAction.scan => '暂时无法打开扫一扫，请重试',
          _FriendCodeAction.copy => '暂时没能复制链接，请重试',
        };
      });
    } finally {
      if (mounted) setState(() => _activeAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = _activeAction == null;

    return Scaffold(
      appBar: AppBar(title: const Text('我的好友二维码')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: const Key('friend-code-card'),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: WanpanColors.surface,
                      borderRadius: BorderRadius.circular(WanpanRadii.large),
                      border: Border.all(color: WanpanColors.border),
                    ),
                    child: Column(
                      children: [
                        _FriendAvatar(user: widget.user),
                        const SizedBox(height: 14),
                        Text(
                          widget.user.nickname,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '用完攀日记扫一扫，加我为岩友',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        LayoutBuilder(
                          builder: (context, constraints) => QrImageView(
                            key: const Key('friend-qr-code'),
                            data: widget.friendUrl.toString(),
                            size: math.min(264, constraints.maxWidth),
                            padding: const EdgeInsets.all(32),
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                            semanticsLabel: '${widget.user.nickname}的好友二维码',
                            errorStateBuilder: (_, _) =>
                                const Center(child: Text('二维码暂时不可用，请稍后重试')),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '确认后发送申请',
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '还没有 App？用微信或相机扫码可前往官网下载',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.onScan != null) ...[
                    WanpanButton(
                      label: '扫一扫添加岩友',
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      loading: _activeAction == _FriendCodeAction.scan,
                      onPressed: enabled
                          ? () => _perform(_FriendCodeAction.scan)
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  WanpanButton(
                    label: '复制好友链接',
                    icon: const Icon(Icons.link_rounded),
                    style: WanpanButtonStyle.secondary,
                    loading: _activeAction == _FriendCodeAction.copy,
                    onPressed: enabled
                        ? () => _perform(_FriendCodeAction.copy)
                        : null,
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _feedback!,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: _hasError
                              ? WanpanColors.danger
                              : WanpanColors.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '好友链接在浏览器中打开官网 App 下载页',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
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

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.user});

  final UserSummary user;

  @override
  Widget build(BuildContext context) {
    const fallback = WanpanMascot(
      key: Key('friend-avatar-fallback'),
      asset: AppAssets.friendsEmptyCat,
      width: 88,
      height: 88,
      fit: BoxFit.contain,
    );
    final avatarUrl = user.avatarUrl?.trim();
    return Semantics(
      image: true,
      label: '${user.nickname}的头像',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: avatarUrl == null || avatarUrl.isEmpty
              ? fallback
              : Image.network(
                  avatarUrl,
                  key: const Key('friend-user-avatar'),
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  frameBuilder: (_, child, frame, _) =>
                      frame == null ? fallback : child,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
