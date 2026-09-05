import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/wanpan_theme.dart';
import '../../core/services/share_service.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_pressable.dart';

/// A local invitation: showing the QR code never publishes account data.
class InviteFriendsScreen extends StatefulWidget {
  const InviteFriendsScreen({
    super.key,
    required this.inviteUrl,
    this.service = const ShareService(),
    this.onShowFriendCode,
  });

  final Uri inviteUrl;
  final ShareService service;
  final VoidCallback? onShowFriendCode;

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

enum _InviteAction { share, copy, preview }

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  final _shareButtonKey = GlobalKey();
  _InviteAction? _activeAction;
  String? _feedback;
  bool _hasError = false;

  Future<void> _perform(_InviteAction action) async {
    if (_activeAction != null) return;
    setState(() {
      _activeAction = action;
      _feedback = null;
      _hasError = false;
    });

    try {
      String? feedback;
      switch (action) {
        case _InviteAction.share:
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
          final box =
              _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize || !box.attached) {
            throw StateError('Share button is unavailable');
          }
          final status = await widget.service.share(
            url: widget.inviteUrl,
            title: '和我一起攀岩吧 | 完攀日记',
            origin: box.localToGlobal(Offset.zero) & box.size,
          );
          feedback = switch (status) {
            ShareResultStatus.success => '已交给所选应用分享',
            ShareResultStatus.dismissed => '已取消分享，可以随时再试',
            ShareResultStatus.unavailable => '可以复制链接后发送给朋友',
          };
        case _InviteAction.copy:
          await widget.service.copy(widget.inviteUrl);
          feedback = '链接已复制，发给朋友一起攀岩吧';
        case _InviteAction.preview:
          await widget.service.preview(widget.inviteUrl);
      }
      if (mounted) setState(() => _feedback = feedback);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _feedback = switch (action) {
          _InviteAction.share => '分享暂时不可用，请重试或复制链接',
          _InviteAction.copy => '暂时没能复制链接，请重试',
          _InviteAction.preview => '暂时无法打开官网，可以复制链接后在浏览器打开',
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
      appBar: AppBar(
        title: const Text('邀请好友'),
        actions: [
          if (widget.onShowFriendCode != null)
            IconButton(
              tooltip: '我的好友二维码',
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              onPressed: enabled ? widget.onShowFriendCode : null,
              icon: const Icon(Icons.qr_code_rounded),
            ),
        ],
      ),
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
                    key: const Key('invite-qr-card'),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: WanpanColors.surface,
                      borderRadius: BorderRadius.circular(WanpanRadii.large),
                      border: Border.all(color: WanpanColors.border),
                    ),
                    child: Column(
                      children: [
                        const ExcludeSemantics(
                          child: WanpanMascot(
                            asset: AppAssets.friendsEmptyCat,
                            width: 112,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '一起上墙，一起完攀',
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '把攀岩的快乐，分享给朋友',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) => QrImageView(
                            key: const Key('invite-qr-code'),
                            data: widget.inviteUrl.toString(),
                            size: math.min(224, constraints.maxWidth),
                            // Leave a full quiet zone, with no artwork over data.
                            padding: const EdgeInsets.all(32),
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                            semanticsLabel: '完攀日记官网下载二维码',
                            errorStateBuilder: (_, _) =>
                                const Center(child: Text('二维码暂时不可用，请分享下方链接')),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '扫码下载完攀日记',
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '记录每次进步，发现更多岩友',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  WanpanButton(
                    key: _shareButtonKey,
                    label: '分享链接',
                    icon: const Icon(Icons.ios_share_rounded),
                    loading: _activeAction == _InviteAction.share,
                    onPressed: enabled
                        ? () => _perform(_InviteAction.share)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  WanpanButton(
                    label: '复制链接',
                    icon: const Icon(Icons.link_rounded),
                    style: WanpanButtonStyle.secondary,
                    loading: _activeAction == _InviteAction.copy,
                    onPressed: enabled
                        ? () => _perform(_InviteAction.copy)
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
                    '好友打开链接，即可前往官网下载 App',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: enabled
                          ? () => _perform(_InviteAction.preview)
                          : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('打开官网'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                    ),
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
