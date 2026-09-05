import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/checkin_models.dart';
import '../../core/models/profile_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/repositories/checkin_repository.dart';
import '../../core/repositories/profile_repository.dart';
import '../auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/milestone_grade_sequence.dart';
import '../../shared/motion/wanpan_motion_sound.dart';
import '../../shared/widgets/wanpan_card.dart';
import '../../shared/widgets/wanpan_lottie_stage.dart';
import '../../shared/widgets/wanpan_mascot.dart';
import '../../shared/widgets/wanpan_milestone_stage.dart';
import '../../shared/widgets/wanpan_pressable.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({
    required this.api,
    required this.session,
    required this.routeId,
    super.key,
    this.grade,
    this.motionSoundPlayer,
    this.routeName,
    this.repository,
  });

  final ApiClient api;
  final SessionController session;
  final String routeId;
  final String? grade;
  final WanpanMotionSoundPlayer? motionSoundPlayer;
  final String? routeName;
  final CheckinRepository? repository;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  late final CheckinRepository _repository =
      widget.repository ?? CheckinRepository(widget.api);
  late final ProfileRepository _profileRepository = ProfileRepository(
    widget.api,
  );
  final _picker = ImagePicker();
  final _captionController = TextEditingController();
  XFile? _video;
  int _attempts = 1;
  bool _syncToSquare = true;
  bool _submitting = false;
  bool _uploading = false;
  bool _preparingVideo = false;
  double _progress = 0;
  String _stage = '';
  CheckinResult? _result;
  MonthDashboard? _currentMonthDashboard;
  bool _motionPreloadStarted = false;
  late final WanpanMotionSoundPlayer _motionSoundPlayer;
  late final bool _ownsMotionSoundPlayer;

  @override
  void initState() {
    super.initState();
    _ownsMotionSoundPlayer = widget.motionSoundPlayer == null;
    _motionSoundPlayer =
        widget.motionSoundPlayer ?? WanpanAssetMotionSoundPlayer();
    if (widget.session.isAuthenticated) {
      unawaited(_prefetchCurrentMonthDashboard());
    }
  }

  Future<void> _prefetchCurrentMonthDashboard() async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    try {
      final dashboard = await _profileRepository.getMonthDashboard(month);
      if (mounted) setState(() => _currentMonthDashboard = dashboard);
    } catch (_) {
      // Milestone feedback is never blocked by optional profile history.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionPreloadStarted) return;
    _motionPreloadStarted = true;
    unawaited(preloadWanpanLottie(context, AppAssets.sendSuccessAnimation));
    unawaited(preloadWanpanLottie(context, AppAssets.gradeMilestoneAnimation));
    unawaited(
      _motionSoundPlayer.preload(const [
        WanpanMotionSoundCue.sendSuccess,
        WanpanMotionSoundCue.gradeMilestone,
      ]),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    if (_ownsMotionSoundPlayer) {
      unawaited(_motionSoundPlayer.dispose());
    } else {
      unawaited(_motionSoundPlayer.stop());
    }
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
    final authorId = widget.session.user?.id;
    final attempts = _attempts;
    final caption = _captionController.text.trim();
    final visibility = _syncToSquare ? 'public' : 'friends';
    setState(() {
      _submitting = true;
      _uploading = selectedVideo != null;
      _progress = 0;
      _stage = selectedVideo == null ? '正在保存打卡…' : '视频上传中…';
    });
    try {
      String? videoUrl;
      if (selectedVideo != null) {
        videoUrl = await _repository.uploadVideo(
          selectedVideo.path,
          onProgress: _onProgress,
          onPhaseChanged: (phase) {
            if (!mounted) return;
            setState(() {
              _preparingVideo = phase == VideoUploadPhase.preparing;
              _uploading = phase == VideoUploadPhase.uploading;
              _progress = 0;
              _stage = _preparingVideo ? '正在压缩视频…' : '视频上传中…';
            });
          },
        );
      }
      if (mounted) {
        setState(() {
          _uploading = false;
          _preparingVideo = false;
          _stage = videoUrl == null ? '正在保存打卡…' : '视频已上传，正在发布…';
          _progress = 1;
        });
      }
      if (!mounted) return;
      if (widget.session.user?.id != authorId) {
        throw const ApiException(
          code: 'UPLOAD_SESSION_CHANGED',
          message: '登录账号已切换，请重新提交',
        );
      }
      final result = await _repository.createCheckin(
        routeId: widget.routeId,
        attempts: attempts,
        videoUrl: videoUrl,
        caption: caption.isEmpty ? null : caption,
        visibility: visibility,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        final message = error is ApiException ? error.message : '$error';
        _toast('提交失败：$message');
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploading = false;
          _preparingVideo = false;
        });
      }
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
          ? _SuccessView(
              result: _result!,
              routeName: widget.routeName,
              grade: widget.grade,
              attempts: _attempts,
              hasVideo: _video != null,
              motionSoundPlayer: _motionSoundPlayer,
              milestoneSequence: MilestoneGradeSequenceResolver.resolve(
                currentMonth: _currentMonthDashboard,
                latestGrade: _result!.milestone?.grade,
              ),
            )
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
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(WanpanRadii.large),
                      clipBehavior: Clip.antiAlias,
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
                    label: _submitting
                        ? (_preparingVideo
                              ? '压缩中…'
                              : (_uploading ? '上传中…' : '正在保存…'))
                        : (_video == null ? '保存完攀' : '上传并打卡'),
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
  const _SuccessView({
    required this.result,
    required this.routeName,
    required this.grade,
    required this.attempts,
    required this.hasVideo,
    required this.motionSoundPlayer,
    required this.milestoneSequence,
  });

  final CheckinResult result;
  final String? routeName;
  final String? grade;
  final int attempts;
  final bool hasVideo;
  final WanpanMotionSoundPlayer motionSoundPlayer;
  final MilestoneGradeSequence milestoneSequence;

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> {
  bool _feedbackScheduled = false;
  Timer? _hapticTimer;

  void _handleAnimationPresented(bool animated) {
    if (_feedbackScheduled) return;
    _feedbackScheduled = true;
    final milestone = widget.result.milestone;
    unawaited(
      widget.motionSoundPlayer.play(
        milestone == null
            ? WanpanMotionSoundCue.sendSuccess
            : WanpanMotionSoundCue.gradeMilestone,
        animated: animated,
      ),
    );
    // The cat lands near frame 12; the final grade lands at frame 38 (60 fps).
    final hapticDelay = animated
        ? Duration(milliseconds: milestone == null ? 180 : 633)
        : Duration.zero;
    if (hapticDelay == Duration.zero) {
      unawaited(_playSuccessHaptic(milestone: milestone != null));
    } else {
      _hapticTimer = Timer(
        hapticDelay,
        () => unawaited(_playSuccessHaptic(milestone: milestone != null)),
      );
    }
  }

  Future<void> _playSuccessHaptic({required bool milestone}) async {
    try {
      if (milestone) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.mediumImpact();
      }
    } catch (_) {
      // The saved record remains successful when haptics are unavailable.
    }
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoPublished =
        widget.hasVideo && widget.result.moderationStatus == 'approved';
    final milestone = widget.result.milestone;
    final headline = milestone == null
        ? '完攀记录已保存！'
        : '新的最高难度 ${milestone.grade}！';
    final grade = milestone?.grade ?? widget.grade ?? 'V?';
    final points = '+${widget.result.pointsEarned} 积分';
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: 232,
                      height: 214,
                      child: milestone == null
                          ? WanpanLottieStage(
                              asset: AppAssets.sendSuccessAnimation,
                              semanticLabel: '黑猫庆祝完攀成功',
                              width: 232,
                              height: 214,
                              onPresented: _handleAnimationPresented,
                              fallback: const WanpanMascot(
                                asset: AppAssets.mascotCelebrate,
                                width: 208,
                                height: 188,
                                radius: 38,
                              ),
                            )
                          : WanpanMilestoneStage(
                              grades: widget.milestoneSequence.grades,
                              semanticLabel: '黑猫庆祝刷新最高难度 $grade',
                              width: 232,
                              height: 214,
                              onPresented: _handleAnimationPresented,
                              fallback: const WanpanMascot(
                                asset: AppAssets.mascotCelebrate,
                                width: 208,
                                height: 188,
                                radius: 38,
                              ),
                            ),
                    ),
                    Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: milestone == null
                            ? WanpanColors.ink
                            : WanpanColors.coralStrong,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      videoPublished ? '视频已上传，可在线路中查看。' : '这次上墙，已经好好记下来了。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: WanpanColors.inkSecondary),
                    ),
                    const SizedBox(height: 22),
                    WanpanCard(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: WanpanColors.coral,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(
                                  color: WanpanColors.coralStrong,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              grade,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.routeName ?? '这条线路',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _SuccessFact(
                                      icon: Icons.replay_rounded,
                                      label: '尝试 ${widget.attempts} 次',
                                    ),
                                    _SuccessFact(
                                      icon: Icons.stars_rounded,
                                      label: points,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: WanpanColors.mintSoft,
                        borderRadius: BorderRadius.circular(WanpanRadii.pill),
                        border: Border.all(color: WanpanColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: WanpanColors.success,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            videoPublished ? '视频已发布' : '完攀记录已保存',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: WanpanColors.success),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    WanpanButton(
                      label: '返回线路',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessFact extends StatelessWidget {
  const _SuccessFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: WanpanColors.surfaceSoft,
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: WanpanColors.coral),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}
