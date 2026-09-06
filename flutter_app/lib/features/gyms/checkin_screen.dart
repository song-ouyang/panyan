import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/wanpan_theme.dart';
import '../../core/models/checkin_models.dart';
import '../../core/models/growth_models.dart';
import '../../core/repositories/growth_repository.dart';
import '../../core/services/publication_request_draft.dart';
import '../../shared/widgets/wanpan_badge_stage.dart';
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
import '../../shared/widgets/wanpan_notice.dart';
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
  late final _growth = GrowthRepository.forSession(widget.api, widget.session);
  PublicationRequestDraft? _draft;
  late final Future<void> _draftReady;
  late String? _sessionToken;
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
    _sessionToken = widget.session.token;
    widget.session.addListener(_sessionChanged);
    _draftReady = _restoreDraft();
    _ownsMotionSoundPlayer = widget.motionSoundPlayer == null;
    _motionSoundPlayer =
        widget.motionSoundPlayer ?? WanpanAssetMotionSoundPlayer();
    if (widget.session.isAuthenticated) {
      unawaited(_prefetchCurrentMonthDashboard());
    }
  }

  Future<void> _restoreDraft() async {
    final owner = widget.session.user?.id;
    if (owner == null) return;
    final token = widget.session.token;
    try {
      final draft = await PublicationRequestDraft.load(
        ownerId: owner,
        kind: 'checkin',
        target: widget.routeId,
      );
      if (!mounted || widget.session.token != token) {
        await draft.clear();
        return;
      }
      _draft = draft;
      final payload = draft.payload;
      if (payload != null) {
        setState(() {
          _attempts = payload['attempts'] as int? ?? 1;
          _captionController.text = payload['caption'] as String? ?? '';
          _syncToSquare = payload['visibility'] == 'public';
        });
      }
    } catch (_) {
      /* Submit retries durable draft loading. */
    }
  }

  void _sessionChanged() {
    if (_sessionToken == widget.session.token) return;
    _sessionToken = widget.session.token;
    final draft = _draft;
    _draft = null;
    if (draft != null) unawaited(draft.clear().catchError((Object _) {}));
    unawaited(_motionSoundPlayer.stop());
    if (mounted) {
      setState(() {
        _result = null;
        _video = null;
        _captionController.clear();
        _submitting = false;
        _currentMonthDashboard = null;
      });
      _toast('登录账号已切换，请重新提交');
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
    widget.session.removeListener(_sessionChanged);
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
    final token = widget.session.token;
    final generation = _growth.sessionGeneration;
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
      await _draftReady;
      if (!mounted ||
          authorId != widget.session.user?.id ||
          widget.session.token != token) {
        return;
      }
      if (_draft == null) await _restoreDraft();
      final draft = _draft;
      if (draft == null) throw StateError('提交草稿未保存，请重试');
      String? videoUrl = draft.payload?['videoUrl'] as String?;
      if (draft.payload == null && selectedVideo != null) {
        videoUrl = await _repository.uploadVideo(
          selectedVideo.path,
          onProgress: (progress) {
            if (widget.session.token == token) _onProgress(progress);
          },
          onPhaseChanged: (phase) {
            if (!mounted || widget.session.token != token) return;
            setState(() {
              _preparingVideo = phase == VideoUploadPhase.preparing;
              _uploading = phase == VideoUploadPhase.uploading;
              _progress = 0;
              _stage = _preparingVideo ? '正在压缩视频…' : '视频上传中…';
            });
          },
        );
      }
      if (mounted && widget.session.token == token) {
        setState(() {
          _uploading = false;
          _preparingVideo = false;
          _stage = videoUrl == null ? '正在保存打卡…' : '视频已上传，正在发布…';
          _progress = 1;
        });
      }
      if (!mounted || widget.session.token != token) return;
      if (widget.session.user?.id != authorId) {
        throw const ApiException(
          code: 'UPLOAD_SESSION_CHANGED',
          message: '登录账号已切换，请重新提交',
        );
      }
      await draft.freeze({
        'routeId': widget.routeId,
        'attempts': attempts,
        'videoUrl': videoUrl,
        'caption': caption.isEmpty ? null : caption,
        'visibility': visibility,
        'operation': 'record',
      });
      if (!mounted || widget.session.token != token) return;
      final payload = draft.payload!;
      final result = await widget.api.inSession(
        token!,
        () => _repository.createCheckin(
          routeId: payload['routeId'] as String,
          attempts: payload['attempts'] as int,
          videoUrl: payload['videoUrl'] as String?,
          caption: payload['caption'] as String?,
          visibility: payload['visibility'] as String,
          clientRequestId: draft.id,
        ),
      );
      if (!mounted ||
          widget.session.token != token ||
          !_growth.isCurrentSession(generation)) {
        return;
      }
      _growth.acceptSnapshot(result.growth, generation: generation);
      setState(() => _result = result);
      unawaited(draft.clear().catchError((Object _) {}));
    } catch (error) {
      if (mounted && widget.session.token == token) {
        if (error is ApiException &&
            [400, 404, 413, 422].contains(error.statusCode)) {
          try {
            await _draft?.unlockAfterRejection();
          } catch (_) {}
          if (!mounted || widget.session.token != token) return;
        }
        final message = error is ApiException ? error.message : '$error';
        _toast('提交失败：$message');
      }
    } finally {
      if (mounted && widget.session.token == token) {
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
    WanpanNotice.show(context, text);
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
              growthRepository: _growth,
              routeName: widget.routeName,
              grade: widget.grade,
              attempts: _attempts,
              hasVideo: _video != null || _draft?.payload?['videoUrl'] != null,
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
                    onTap: _submitting || _draft?.payload != null
                        ? null
                        : _showSourcePicker,
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
                        enabled: !_submitting && _draft?.payload == null,
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
                    enabled: !_submitting && _draft?.payload == null,
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
                        onChanged: _submitting || _draft?.payload != null
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
                  if (_draft?.payload != null && !_submitting)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('上次提交还未确认，重试将继续保存同一份记录。'),
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
    required this.growthRepository,
  });

  final CheckinResult result;
  final GrowthRepository growthRepository;
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
  GrowthPresentation? _presentation;
  bool _resolvingGrowth = true;
  bool _growthFailed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_resolveGrowth());
  }

  Future<void> _resolveGrowth() async {
    if (widget.result.growth == null) {
      setState(() => _resolvingGrowth = false);
      return;
    }
    final generation = widget.growthRepository.sessionGeneration;
    setState(() {
      _resolvingGrowth = true;
      _growthFailed = false;
    });
    try {
      final presentation = await widget.growthRepository.consumePresentation();
      if (mounted && widget.growthRepository.isCurrentSession(generation)) {
        setState(() => _presentation = presentation);
      }
    } catch (_) {
      if (mounted && widget.growthRepository.isCurrentSession(generation)) {
        setState(() => _growthFailed = true);
      }
    } finally {
      if (mounted) setState(() => _resolvingGrowth = false);
    }
  }

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
    final headline = _presentation != null
        ? 'Lv.${_presentation!.toLevel} · ${_presentation!.levelName}'
        : milestone == null
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
                      child: _resolvingGrowth
                          ? const Center(
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 76,
                                color: WanpanColors.success,
                              ),
                            )
                          : _presentation != null
                          ? WanpanBadgeStage(
                              level: _presentation!.toLevel,
                              size: 214,
                              soundPlayer: widget.motionSoundPlayer,
                            )
                          : milestone == null
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
                    if (_presentation != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _presentation!.newBadgeCount > 1
                            ? '这次点亮了 ${_presentation!.newBadgeCount} 枚徽章'
                            : '点亮了一枚新的账户徽章',
                        textAlign: TextAlign.center,
                      ),
                      if (milestone != null)
                        Text(
                          '同时刷新最高难度 ${milestone.grade}',
                          textAlign: TextAlign.center,
                        ),
                    ],
                    if (_growthFailed)
                      TextButton(
                        onPressed: _resolveGrowth,
                        child: const Text('记录已保存，徽章同步失败 · 重试'),
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
