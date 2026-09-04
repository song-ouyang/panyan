import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/wanpan_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/app_assets.dart';
import '../../../shared/widgets/wanpan_pressable.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';
import '../domain/auth_return_path.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    required this.api,
    required this.session,
    required this.repository,
    required this.returnTo,
    this.editing = false,
    super.key,
  });

  final ApiClient api;
  final SessionController session;
  final AuthRepository repository;
  final String returnTo;
  final bool editing;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nickname;
  late final TextEditingController _bio;
  XFile? _avatar;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.session.user;
    _nickname = TextEditingController(
      text: user?.nickname == '岩友' ? '' : user?.nickname ?? '',
    );
    _bio = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1200,
    );
    if (picked != null && mounted) setState(() => _avatar = picked);
  }

  Future<void> _save() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = '请填写一个昵称。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var avatarUrl = widget.session.user?.avatarUrl;
      if (_avatar != null) {
        avatarUrl = await widget.api.uploadFile(_avatar!.path);
      }
      final user = await widget.repository.updateProfile(
        nickname: nickname,
        avatarUrl: avatarUrl,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
      );
      await widget.session.updateUser(user);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _finish();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _finish() {
    context.go(safeAuthReturnTo(widget.returnTo));
  }

  ImageProvider<Object>? get _avatarImage {
    if (_avatar != null) return FileImage(File(_avatar!.path));
    final remote = widget.session.user?.avatarUrl;
    return remote == null ? null : NetworkImage(remote);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.editing && !_saving,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.editing ? '编辑个人资料' : '完善个人资料')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 42),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.editing ? '让岩友认出你' : '给你的攀岩记录留个名字',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontSize: 34, letterSpacing: -1.2),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 190,
                      height: 5,
                      decoration: BoxDecoration(
                        color: WanpanColors.coralSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Semantics(
                      button: true,
                      label: '选择头像',
                      child: WanpanPressable(
                        onTap: _saving ? null : _pickAvatar,
                        borderRadius: BorderRadius.circular(WanpanRadii.pill),
                        child: SizedBox(
                          width: 276,
                          height: 246,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: 69,
                                top: 46,
                                child: Container(
                                  width: 164,
                                  height: 164,
                                  decoration: BoxDecoration(
                                    color: WanpanColors.coralSoft,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0x66F3BBA9),
                                      width: 2,
                                    ),
                                    image: _avatarImage == null
                                        ? null
                                        : DecorationImage(
                                            image: ResizeImage.resizeIfNeeded(
                                              512,
                                              512,
                                              _avatarImage!,
                                            ),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  alignment: Alignment.center,
                                  child: _avatarImage == null
                                      ? const Icon(
                                          Icons.person_rounded,
                                          size: 70,
                                          color: WanpanColors.coral,
                                        )
                                      : null,
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Image.asset(
                                    AppAssets.profilePeekCat,
                                    cacheWidth: 780,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 34,
                                bottom: 24,
                                child: Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: WanpanColors.coral,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x22000000),
                                        offset: Offset(0, 5),
                                        blurRadius: 9,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ProfileField(
                    label: '昵称',
                    hint: '请输入你的昵称',
                    controller: _nickname,
                    enabled: !_saving,
                    maxLength: 32,
                    minHeight: 132,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  _ProfileField(
                    label: '个人简介（可选）',
                    hint: '介绍一下你自己吧，喜欢的岩场、风格或小目标～',
                    controller: _bio,
                    enabled: !_saving,
                    maxLength: 120,
                    minHeight: 164,
                    maxLines: 4,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: WanpanColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  WanpanButton(
                    key: const Key('save-profile'),
                    label: widget.editing ? '保存修改' : '开始记录',
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.maxLength,
    required this.minHeight,
    this.maxLines = 1,
    this.textInputAction,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final int maxLength;
  final double minHeight;
  final int maxLines;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) => Container(
    height: minHeight,
    padding: const EdgeInsets.fromLTRB(18, 17, 18, 8),
    decoration: BoxDecoration(
      color: WanpanColors.surface.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: WanpanColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Expanded(
          child: TextField(
            key: label == '昵称' ? const Key('profile-nickname') : null,
            controller: controller,
            enabled: enabled,
            maxLength: maxLength,
            maxLines: maxLines,
            textInputAction: textInputAction,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => Text(
              '${value.text.characters.length}/$maxLength',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    ),
  );
}
