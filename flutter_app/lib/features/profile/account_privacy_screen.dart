import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/wanpan_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/repositories/profile_repository.dart';
import '../../shared/widgets/wanpan_pressable.dart';
import '../auth/application/session_controller.dart';

class AccountPrivacyScreen extends StatefulWidget {
  const AccountPrivacyScreen({
    required this.api,
    required this.session,
    super.key,
  });

  final ApiClient api;
  final SessionController session;

  @override
  State<AccountPrivacyScreen> createState() => _AccountPrivacyScreenState();
}

class _AccountPrivacyScreenState extends State<AccountPrivacyScreen> {
  static const _privacyUrl = 'https://panyan-api.gblh.cloud/privacy';
  static const _choicesUrl = 'https://panyan-api.gblh.cloud/privacy-choices';
  static const _termsUrl = 'https://panyan-api.gblh.cloud/terms';

  late final ProfileRepository _repository = ProfileRepository(widget.api);
  bool _deleting = false;

  Future<void> _open(String value) async {
    final opened = await launchUrl(
      Uri.parse(value),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法打开网页，请稍后再试。')));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: WanpanColors.danger,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final first = await _confirm(
      title: '注销并删除账号？',
      message: '个人资料、攀岩记录、动态、评论、岩友和约爬数据将被删除，操作通常无法恢复。',
      action: '继续',
    );
    if (!first || !mounted) return;
    final finalConfirmation = await _confirm(
      title: '最后确认',
      message: '确定永久注销“完攀日记”账号吗？完成后本机会立即退出登录。',
      action: '永久删除',
    );
    if (!finalConfirmation || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _repository.deleteAccount();
      await widget.session.signOut();
      if (mounted) context.go('/gyms');
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('账号暂时没有删除成功，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号与隐私')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Text('规则与隐私', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _PrivacyTile(
            icon: Icons.privacy_tip_outlined,
            title: '隐私政策',
            subtitle: '了解我们如何处理和保护信息',
            onTap: () => _open(_privacyUrl),
          ),
          const SizedBox(height: 10),
          _PrivacyTile(
            icon: Icons.tune_rounded,
            title: '隐私选择与账号删除',
            subtitle: '查看、更正、删除和权限管理方式',
            onTap: () => _open(_choicesUrl),
          ),
          const SizedBox(height: 10),
          _PrivacyTile(
            icon: Icons.description_outlined,
            title: '用户协议',
            subtitle: '查看使用规则与安全提示',
            onTap: () => _open(_termsUrl),
          ),
          const SizedBox(height: 28),
          Text('账号管理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: WanpanColors.surface,
              borderRadius: BorderRadius.circular(WanpanRadii.large),
              border: Border.all(color: WanpanColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '注销账号会发生什么？',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '账号资料和关联记录将按隐私政策处理，轮换备份最长保留 14 天。删除后通常无法恢复。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('delete-account'),
                    onPressed: _deleting ? null : _deleteAccount,
                    style: FilledButton.styleFrom(
                      backgroundColor: WanpanColors.danger,
                    ),
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                    label: Text(_deleting ? '正在删除…' : '注销并删除账号'),
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

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      pressedScale: .985,
      child: Container(
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
                color: WanpanColors.coralSoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: WanpanColors.coralStrong),
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
            const Icon(
              Icons.open_in_new_rounded,
              color: WanpanColors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
