import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/wanpan_theme.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../auth/application/session_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.session, super.key});

  final SessionController session;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    // Leave this protected page before the session notifies the router so
    // signed-out users land on the public app instead of an unnecessary login.
    context.go('/gyms');
    await widget.session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          if (user != null) ...[
            _CurrentAccount(nickname: user.nickname, avatarUrl: user.avatarUrl),
            const SizedBox(height: 26),
          ],
          Text('账号', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _SettingsTile(
            key: const Key('account-privacy-tile'),
            icon: Icons.shield_outlined,
            iconColor: WanpanColors.grape,
            iconBackground: WanpanColors.grapeSoft,
            title: '账号与隐私',
            subtitle: '隐私政策、用户协议与账号注销',
            onTap: () => context.push('/profile/privacy'),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            key: const Key('settings-sign-out'),
            icon: Icons.logout_rounded,
            iconColor: WanpanColors.danger,
            iconBackground: WanpanColors.coralSoft,
            title: _signingOut ? '正在退出…' : '退出登录',
            subtitle: '本机的登录凭证会安全移除',
            onTap: _signingOut ? null : _signOut,
            trailing: _signingOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _CurrentAccount extends StatelessWidget {
  const _CurrentAccount({required this.nickname, required this.avatarUrl});

  final String nickname;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WanpanColors.surface,
        borderRadius: BorderRadius.circular(WanpanRadii.large),
        border: Border.all(color: WanpanColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: WanpanColors.surface,
            backgroundImage: hasAvatar
                ? ResizeImage.resizeIfNeeded(168, 168, NetworkImage(avatarUrl!))
                : null,
            child: hasAvatar
                ? null
                : Text(
                    nickname.trim().isEmpty ? '岩' : nickname.characters.first,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: WanpanColors.coralStrong),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text('当前登录账号', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
          const Icon(
            Icons.verified_user_outlined,
            color: WanpanColors.inkSecondary,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      onTap: onTap,
      semanticLabel: title,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      pressedScale: .985,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(color: WanpanColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WanpanColors.muted,
                ),
          ],
        ),
      ),
    );
  }
}
