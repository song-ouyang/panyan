import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/checkin_models.dart';
import '../../core/network/api_client.dart';
import '../../core/repositories/checkin_repository.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_pressable.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({
    required this.api,
    required this.session,
    required this.routeId,
    super.key,
    this.grade,
    this.routeName,
  });

  final ApiClient api;
  final SessionController session;
  final String routeId;
  final String? grade;
  final String? routeName;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  late final CheckinRepository _repository = CheckinRepository(widget.api);
  final _picker = ImagePicker();
  final _captionController = TextEditingController();
  XFile? _video;
  int _attempts = 1;
  bool _syncToSquare = true;
  bool _submitting = false;
  double _progress = 0;
  String _stage = '';
  CheckinResult? _result;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _chooseVideo(ImageSource source) async {
    final video = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (video != null && mounted) setState(() => _video = video);
  }

  Future<void> _showSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_library_rounded),
                title: const Text('从相册选择视频'),
                onTap: () {
                  Navigator.pop(context);
                  _chooseVideo(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: const Text('现在拍摄'),
                onTap: () {
                  Navigator.pop(context);
                  _chooseVideo(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!widget.session.isAuthenticated) {
      _toast('登录状态已失效，请重新登录');
      return;
    }

    // Snapshot every mutable field before the first await. This keeps the
    // payload stable for the entire upload and avoids touching disposed form
    // controllers if the widget lifecycle changes unexpectedly.
    final selectedVideo = _video;
    final attempts = _attempts;
    final caption = _captionController.text.trim();
    final visibility = _syncToSquare ? 'public' : 'friends';
    setState(() {
      _submitting = true;
      _progress = 0;
      _stage = selectedVideo == null ? '正在保存打卡…' : '正在上传视频…';
    });
    try {
      String? videoUrl;
      if (selectedVideo != null) {
        final path = selectedVideo.path;
        final size = await File(path).length();
        final filename = selectedVideo.name.trim().isEmpty
            ? File(path).uri.pathSegments.last
            : selectedVideo.name.trim();
        final lowerName = filename.toLowerCase();
        final supportsMultipart =
            lowerName.endsWith('.mp4') || lowerName.endsWith('.mov');
        final mimeType = lowerName.endsWith('.mov')
            ? 'video/quicktime'
            : 'video/mp4';
        if (supportsMultipart && size >= 5 * 1024 * 1024) {
          try {
            videoUrl = await _repository.uploadVideoMultipart(
              path,
              filename: filename,
              mimeType: mimeType,
              onProgress: _onProgress,
            );
          } catch (_) {
            if (!mounted) rethrow;
            setState(() {
              _progress = 0;
              _stage = '分片上传不可用，切换普通上传…';
            });
            videoUrl = await _repository.uploadMedia(
              path,
              onProgress: _onProgress,
            );
          }
        } else {
          videoUrl = await _repository.uploadMedia(
            path,
            onProgress: _onProgress,
          );
        }
      }
      if (mounted) {
        setState(() {
          _stage = '正在生成完攀记录…';
          _progress = 1;
        });
      }
      final result = await _repository.createCheckin(
        routeId: widget.routeId,
        attempts: attempts,
        videoUrl: videoUrl,
        caption: caption.isEmpty ? null : caption,
        visibility: visibility,
      );
      await HapticFeedback.heavyImpact();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) _toast('提交失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onProgress(double progress) {
    if (mounted) setState(() => _progress = progress);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _submitting) _toast('正在提交，请稍候');
      },
      child: _result != null
          ? _SuccessView(result: _result!)
          : Scaffold(
              appBar: AppBar(title: const Text('视频打卡')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  WanpanCard(
                    color: WanpanColors.coralSoft,
                    borderColor: Colors.transparent,
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: WanpanColors.coral,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Text(
                            widget.grade ?? 'V?',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.routeName ?? '这条线路',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '记录今天的完攀',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('完攀视频', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  _VideoPicker(
                    video: _video,
                    onTap: _submitting ? null : _showSourcePicker,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '尝试次数',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      _AttemptStepper(
                        value: _attempts,
                        enabled: !_submitting,
                        onChanged: (value) => setState(() => _attempts = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('写点感受', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _captionController,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 300,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      hintText: '比如：最后一步终于稳住了！',
                    ),
                  ),
                  const SizedBox(height: 6),
                  WanpanCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile.adaptive(
                      value: _syncToSquare,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _syncToSquare = value),
                      secondary: Icon(
                        _syncToSquare
                            ? Icons.public_rounded
                            : Icons.people_alt_rounded,
                        color: WanpanColors.coral,
                      ),
                      title: const Text('同步到广场'),
                      subtitle: Text(
                        _syncToSquare ? '所有岩友都可以看到这次完攀' : '关闭后，仅你的岩友可在朋友圈看到',
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                    ),
                  ),
                  if (_submitting) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _stage,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text('${(_progress * 100).round()}%'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                        minHeight: 9,
                        color: WanpanColors.coral,
                        backgroundColor: WanpanColors.coralSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  WanpanButton(
                    label: _video == null ? '保存完攀' : '上传并打卡',
                    loading: _submitting,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
    );
  }
}

class _VideoPicker extends StatelessWidget {
  const _VideoPicker({required this.video, required this.onTap});

  final XFile? video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WanpanCard(
    onTap: onTap,
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: video == null
                ? WanpanColors.surfaceSoft
                : WanpanColors.coralSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            video == null ? Icons.add_rounded : Icons.check_rounded,
            color: video == null ? WanpanColors.muted : WanpanColors.coral,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video == null ? '选择或拍摄视频' : video!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                video == null ? '支持 MP4 / MOV，最长 5 分钟' : '点击可重新选择',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AttemptStepper extends StatelessWidget {
  const _AttemptStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: WanpanColors.surfaceSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          onPressed: enabled && value < 99 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}

class _SuccessView extends StatefulWidget {
  const _SuccessView({required this.result});

  final CheckinResult result;

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.result.moderationStatus == 'pending';
    final milestone = widget.result.milestone;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              AnimatedScale(
                scale: _visible ? 1 : .88,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    AppAssets.mascotCelebrate,
                    width: 210,
                    height: 188,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                milestone == null ? '完攀记录已保存！' : '第一次完成 ${milestone.grade}！',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                pending
                    ? '视频正在审核，通过后会进入线路榜单，并结算 ${widget.result.pendingPoints} 积分。'
                    : '获得 ${widget.result.pointsEarned} 积分，继续保持！',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: WanpanColors.inkSecondary),
              ),
              const Spacer(),
              WanpanButton(
                label: '完成',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
