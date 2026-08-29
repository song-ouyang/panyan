import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/wanpan_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/wanpan_pressable.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';

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
    final destination = widget.returnTo.startsWith('/')
        ? widget.returnTo
        : '/gyms';
    context.go(destination);
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
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.editing ? '让岩友认出你' : '给你的攀岩记录留个名字',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Semantics(
                      button: true,
                      label: '选择头像',
                      child: InkWell(
                        onTap: _saving ? null : _pickAvatar,
                        customBorder: const CircleBorder(),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: WanpanColors.coralSoft,
                              backgroundImage: _avatarImage,
                              child: _avatarImage == null
                                  ? const Icon(
                                      Icons.person_rounded,
                                      size: 44,
                                      color: WanpanColors.coral,
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: WanpanColors.ink,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const Key('profile-nickname'),
                    controller: _nickname,
                    enabled: !_saving,
                    maxLength: 32,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      hintText: '例如：爱爬橙线的小欧',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bio,
                    enabled: !_saving,
                    maxLength: 120,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '个人简介（可选）',
                      hintText: '你喜欢什么类型的线路？',
                    ),
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
                  const SizedBox(height: 18),
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
