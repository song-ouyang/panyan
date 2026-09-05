import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/models/profile_models.dart';
import 'package:wanpan_diary/shared/app_assets.dart';
import 'package:wanpan_diary/shared/motion/milestone_grade_sequence.dart';
import 'package:wanpan_diary/shared/motion/wanpan_motion.dart';
import 'package:wanpan_diary/shared/motion/wanpan_motion_sound.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_lottie_stage.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_milestone_stage.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

/// Debug-only gallery for reviewing Wanpan's four one-shot Lottie scenes.
///
/// Run with:
/// `flutter run -d DEVICE_ID -t tool/motion_preview_main.dart`
///
/// Optionally override the milestone trail without requiring login/API state:
/// `flutter run -d DEVICE_ID -t tool/motion_preview_main.dart`
/// `  --dart-define=MOTION_MILESTONE_GRADES=V2,V4,V5`
void main() {
  runApp(const MotionPreviewApp());
}

const _milestoneGradesFromEnvironment = String.fromEnvironment(
  'MOTION_MILESTONE_GRADES',
);

/// Public so the debug gallery can be exercised by focused widget tests or a
/// host that already owns the signed-in user's [MonthDashboard].
class MotionPreviewApp extends StatelessWidget {
  const MotionPreviewApp({
    super.key,
    this.currentMonthDashboard,
    this.configuredMilestoneGrades = _milestoneGradesFromEnvironment,
    this.motionSoundPlayer,
    this.referenceDate,
  });

  final MonthDashboard? currentMonthDashboard;
  final String? configuredMilestoneGrades;
  final WanpanMotionSoundPlayer? motionSoundPlayer;
  final DateTime? referenceDate;

  @override
  Widget build(BuildContext context) {
    final milestoneSequence = MilestoneGradeSequenceResolver.resolve(
      configured: configuredMilestoneGrades,
      currentMonth: currentMonthDashboard,
      now: referenceDate,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '完攀动效实验室',
      theme: WanpanTheme.light(),
      home: _MotionGalleryScreen(
        initialMilestoneSequence: milestoneSequence,
        motionSoundPlayer: motionSoundPlayer,
      ),
    );
  }
}

enum _MotionSceneKind { send, record, milestone, ranking }

class _MotionScene {
  const _MotionScene({
    required this.kind,
    required this.shortTitle,
    required this.title,
    required this.brief,
    required this.asset,
    required this.semanticLabel,
    required this.accent,
    required this.tint,
    required this.fallbackAsset,
    required this.soundCue,
  });

  final _MotionSceneKind kind;
  final String shortTitle;
  final String title;
  final String brief;
  final String asset;
  final String semanticLabel;
  final Color accent;
  final Color tint;
  final String fallbackAsset;
  final WanpanMotionSoundCue soundCue;
}

const _scenes = <_MotionScene>[
  _MotionScene(
    kind: _MotionSceneKind.send,
    shortTitle: '完攀',
    title: '完攀，太棒了！',
    brief: '黑猫张开双爪放出烟花，把这次真实完攀好好庆祝一下。',
    asset: AppAssets.sendSuccessAnimation,
    semanticLabel: '黑猫张开双爪放烟花庆祝完攀',
    accent: WanpanColors.coral,
    tint: WanpanColors.coralSoft,
    fallbackAsset: AppAssets.mascotCelebrate,
    soundCue: WanpanMotionSoundCue.sendSuccess,
  ),
  _MotionScene(
    kind: _MotionSceneKind.record,
    shortTitle: '记录',
    title: '记录成功',
    brief: '小猫用笔画完这次攀爬记录，再点亮一枚清楚的完成勾。',
    asset: AppAssets.routePublishedAnimation,
    semanticLabel: '黑猫用笔完成记录并点亮勾选',
    accent: WanpanColors.grape,
    tint: WanpanColors.grapeSoft,
    fallbackAsset: AppAssets.routeMapCat,
    soundCue: WanpanMotionSoundCue.routePublished,
  ),
  _MotionScene(
    kind: _MotionSceneKind.milestone,
    shortTitle: '里程碑',
    title: '难度进阶里程碑',
    brief: '从最近的 V 级记录走到新里程碑；没有本月数据时使用 V1 → V2 → V3。',
    asset: AppAssets.gradeMilestoneAnimation,
    semanticLabel: '黑猫庆祝难度逐级进阶',
    accent: WanpanColors.sunflower,
    tint: WanpanColors.sunflowerSoft,
    fallbackAsset: AppAssets.mascotCelebrate,
    soundCue: WanpanMotionSoundCue.gradeMilestone,
  ),
  _MotionScene(
    kind: _MotionSceneKind.ranking,
    shortTitle: '榜单',
    title: '榜单鼓励',
    brief: '榜单暂空时的非循环鼓励：黑猫从领奖台后探出，邀请完成第一条线路。',
    asset: AppAssets.rankingEncouragementAnimation,
    semanticLabel: '榜单空状态鼓励动画',
    accent: WanpanColors.sky,
    tint: WanpanColors.skySoft,
    fallbackAsset: AppAssets.mascotWelcome,
    soundCue: WanpanMotionSoundCue.rankingEncouragement,
  ),
];

class _MotionGalleryScreen extends StatefulWidget {
  const _MotionGalleryScreen({
    required this.initialMilestoneSequence,
    this.motionSoundPlayer,
  });

  final MilestoneGradeSequence initialMilestoneSequence;
  final WanpanMotionSoundPlayer? motionSoundPlayer;

  @override
  State<_MotionGalleryScreen> createState() => _MotionGalleryScreenState();
}

class _MotionGalleryScreenState extends State<_MotionGalleryScreen> {
  static const _frameBudgetMs = 1000 / 60;
  static const _timingWindowDuration = Duration(milliseconds: 1400);

  final _pageController = PageController();
  final _replayVersions = List<int>.filled(_scenes.length, 0);
  Timer? _timingWindow;
  int _selectedIndex = 0;
  bool _reduceMotion = false;
  bool _collectingTimings = true;
  int _sampledFrames = 0;
  int _slowFrames = 0;
  double _maxBuildMs = 0;
  double _maxRasterMs = 0;
  late MilestoneGradeSequence _milestoneSequence;
  late final WanpanMotionSoundPlayer _motionSoundPlayer;
  late final bool _ownsMotionSoundPlayer;

  @override
  void initState() {
    super.initState();
    _ownsMotionSoundPlayer = widget.motionSoundPlayer == null;
    _motionSoundPlayer =
        widget.motionSoundPlayer ?? WanpanAssetMotionSoundPlayer();
    _milestoneSequence = widget.initialMilestoneSequence;
    unawaited(_motionSoundPlayer.preload(WanpanMotionSoundCue.values));
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
    _armTimingWindow();
  }

  @override
  void dispose() {
    _timingWindow?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _pageController.dispose();
    if (_ownsMotionSoundPlayer) {
      unawaited(_motionSoundPlayer.dispose());
    } else {
      unawaited(_motionSoundPlayer.stop());
    }
    super.dispose();
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!_collectingTimings) return;
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      _sampledFrames += 1;
      if (buildMs > _maxBuildMs) _maxBuildMs = buildMs;
      if (rasterMs > _maxRasterMs) _maxRasterMs = rasterMs;
      if (buildMs > _frameBudgetMs || rasterMs > _frameBudgetMs) {
        _slowFrames += 1;
      }
    }
  }

  void _armTimingWindow() {
    _timingWindow?.cancel();
    _timingWindow = Timer(_timingWindowDuration, () {
      if (!mounted) return;
      setState(() => _collectingTimings = false);
    });
  }

  void _startTimingWindow({bool notify = true}) {
    void reset() {
      _collectingTimings = true;
      _sampledFrames = 0;
      _slowFrames = 0;
      _maxBuildMs = 0;
      _maxRasterMs = 0;
    }

    if (notify) {
      setState(reset);
    } else {
      reset();
    }
    _armTimingWindow();
  }

  void _selectScene(int index) {
    if (index == _selectedIndex || !_pageController.hasClients) return;
    unawaited(_motionSoundPlayer.stop());
    _startTimingWindow();
    if (_reduceMotion) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: WanpanMotion.selection,
        curve: WanpanMotion.easeOut,
      );
    }
  }

  void _replay() {
    unawaited(_motionSoundPlayer.stop());
    _startTimingWindow(notify: false);
    setState(() => _replayVersions[_selectedIndex] += 1);
  }

  void _setReduceMotion(bool value) {
    if (value == _reduceMotion) return;
    unawaited(_motionSoundPlayer.stop());
    _startTimingWindow(notify: false);
    setState(() {
      _reduceMotion = value;
      _replayVersions[_selectedIndex] += 1;
    });
  }

  Future<void> _configureMilestoneGrades() async {
    final grades = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _MilestoneGradeEditorSheet(initialGrades: _milestoneSequence.grades),
    );
    if (!mounted || grades == null) return;
    final configured = MilestoneGradeSequenceResolver.resolve(
      configured: grades.join(','),
    );
    final milestoneIndex = _scenes.indexWhere(
      (scene) => scene.kind == _MotionSceneKind.milestone,
    );
    unawaited(_motionSoundPlayer.stop());
    _startTimingWindow(notify: false);
    setState(() {
      _milestoneSequence = configured;
      _replayVersions[milestoneIndex] += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(disableAnimations: _reduceMotion),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WanpanSpacing.page,
              WanpanSpacing.sm,
              WanpanSpacing.page,
              WanpanSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GalleryHeader(
                  reduceMotion: _reduceMotion,
                  onReduceMotionChanged: _setReduceMotion,
                ),
                const SizedBox(height: WanpanSpacing.md),
                _ScenePicker(
                  selectedIndex: _selectedIndex,
                  onSelected: _selectScene,
                ),
                const SizedBox(height: WanpanSpacing.sm),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _scenes.length,
                    onPageChanged: (index) {
                      if (index == _selectedIndex) return;
                      unawaited(_motionSoundPlayer.stop());
                      if (!_collectingTimings) {
                        _startTimingWindow(notify: false);
                      }
                      setState(() {
                        _selectedIndex = index;
                        _replayVersions[index] += 1;
                      });
                    },
                    itemBuilder: (context, index) {
                      final scene = _scenes[index];
                      return _ScenePage(
                        scene: scene,
                        selected: index == _selectedIndex,
                        replayVersion: _replayVersions[index],
                        reduceMotion: _reduceMotion,
                        milestoneSequence: _milestoneSequence,
                        onConfigureMilestone: _configureMilestoneGrades,
                        onAnimationPresented: (animated) {
                          if (index != _selectedIndex) return;
                          unawaited(
                            _motionSoundPlayer.play(
                              scene.soundCue,
                              animated: animated,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: WanpanSpacing.sm),
                _FrameTimingPanel(
                  collecting: _collectingTimings,
                  sampledFrames: _sampledFrames,
                  slowFrames: _slowFrames,
                  maxBuildMs: _maxBuildMs,
                  maxRasterMs: _maxRasterMs,
                ),
                const SizedBox(height: WanpanSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _StepButton(
                        icon: Icons.arrow_back_rounded,
                        label: '上一个',
                        enabled: _selectedIndex > 0,
                        onTap: () => _selectScene(_selectedIndex - 1),
                      ),
                    ),
                    const SizedBox(width: WanpanSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: WanpanButton(
                        label: _reduceMotion ? '刷新最终帧' : '重播动效',
                        icon: const Icon(Icons.replay_rounded),
                        onPressed: _replay,
                      ),
                    ),
                    const SizedBox(width: WanpanSpacing.sm),
                    Expanded(
                      child: _StepButton(
                        icon: Icons.arrow_forward_rounded,
                        label: '下一个',
                        enabled: _selectedIndex < _scenes.length - 1,
                        onTap: () => _selectScene(_selectedIndex + 1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FrameTimingPanel extends StatelessWidget {
  const _FrameTimingPanel({
    required this.collecting,
    required this.sampledFrames,
    required this.slowFrames,
    required this.maxBuildMs,
    required this.maxRasterMs,
  });

  final bool collecting;
  final int sampledFrames;
  final int slowFrames;
  final double maxBuildMs;
  final double maxRasterMs;

  String _milliseconds(double value) {
    if (sampledFrames == 0) return '—';
    return '${value.toStringAsFixed(1)} ms';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: collecting
          ? '帧性能采样中'
          : '最大构建耗时 ${_milliseconds(maxBuildMs)}，'
                '最大光栅耗时 ${_milliseconds(maxRasterMs)}，'
                '慢帧 $slowFrames',
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: WanpanColors.surfaceSoft,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(color: WanpanColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: WanpanColors.mintSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                collecting ? Icons.speed_rounded : Icons.check_rounded,
                color: WanpanColors.success,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimingMetric(
                label: '最大 build',
                value: collecting ? '采样中…' : _milliseconds(maxBuildMs),
              ),
            ),
            Expanded(
              child: _TimingMetric(
                label: '最大 raster',
                value: collecting ? '采样中…' : _milliseconds(maxRasterMs),
              ),
            ),
            Expanded(
              child: _TimingMetric(
                label: '>16.7 ms',
                value: collecting ? '采样中…' : '$slowFrames / $sampledFrames',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimingMetric extends StatelessWidget {
  const _TimingMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: const TextStyle(
            color: WanpanColors.ink,
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w900,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.reduceMotion,
    required this.onReduceMotionChanged,
  });

  final bool reduceMotion;
  final ValueChanged<bool> onReduceMotionChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '动效实验室',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: WanpanSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: WanpanColors.coralSoft,
                      borderRadius: BorderRadius.circular(WanpanRadii.pill),
                    ),
                    child: const Text(
                      'DEBUG',
                      style: TextStyle(
                        color: WanpanColors.coralStrong,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '单次播放 · 稳定定格 · 60 fps',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Semantics(
          toggled: reduceMotion,
          label: '减少动态效果',
          child: Column(
            children: [
              Switch.adaptive(
                value: reduceMotion,
                activeTrackColor: WanpanColors.grape,
                onChanged: onReduceMotionChanged,
              ),
              Text(
                '减少动效',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: reduceMotion ? WanpanColors.grape : WanpanColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScenePicker extends StatelessWidget {
  const _ScenePicker({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 45,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _scenes.length,
        separatorBuilder: (_, _) => const SizedBox(width: WanpanSpacing.xs),
        itemBuilder: (context, index) {
          final scene = _scenes[index];
          final selected = index == selectedIndex;
          return WanpanPressable(
            semanticLabel: '预览${scene.title}',
            borderRadius: BorderRadius.circular(WanpanRadii.pill),
            pressedScale: .96,
            enableHaptics: true,
            onTap: () => onSelected(index),
            child: AnimatedContainer(
              duration: WanpanMotion.duration(context, WanpanMotion.selection),
              curve: WanpanMotion.curve(context),
              constraints: const BoxConstraints(minWidth: 82, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scene.tint : WanpanColors.surface,
                borderRadius: BorderRadius.circular(WanpanRadii.pill),
                border: Border.all(
                  color: selected ? scene.accent : WanpanColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                scene.shortTitle,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? scene.accent : WanpanColors.inkSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScenePage extends StatelessWidget {
  const _ScenePage({
    required this.scene,
    required this.selected,
    required this.replayVersion,
    required this.reduceMotion,
    required this.milestoneSequence,
    required this.onConfigureMilestone,
    required this.onAnimationPresented,
  });

  final _MotionScene scene;
  final bool selected;
  final int replayVersion;
  final bool reduceMotion;
  final MilestoneGradeSequence milestoneSequence;
  final VoidCallback onConfigureMilestone;
  final WanpanLottiePresented onAnimationPresented;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.large),
          border: Border.all(color: WanpanColors.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stageSize = (constraints.maxHeight * .58).clamp(230.0, 350.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _PlaybackBadge(
                        reduceMotion: reduceMotion,
                        accent: scene.accent,
                        tint: scene.tint,
                      ),
                      if (scene.kind == _MotionSceneKind.milestone) ...[
                        const Spacer(),
                        _MilestoneSequenceButton(
                          sequence: milestoneSequence,
                          onTap: onConfigureMilestone,
                        ),
                      ],
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scene.tint.withValues(alpha: .42),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: stageSize,
                          child: scene.kind == _MotionSceneKind.milestone
                              ? WanpanMilestoneStage(
                                  key: ValueKey(
                                    '${scene.asset}-$replayVersion-'
                                    '$reduceMotion-${milestoneSequence.displayLabel}',
                                  ),
                                  grades: milestoneSequence.grades,
                                  semanticLabel: scene.semanticLabel,
                                  play: selected,
                                  width: stageSize,
                                  height: stageSize,
                                  onPresented: onAnimationPresented,
                                  fallback: _SceneFallback(scene: scene),
                                )
                              : WanpanLottieStage(
                                  key: ValueKey(
                                    '${scene.asset}-$replayVersion-'
                                    '$reduceMotion',
                                  ),
                                  asset: scene.asset,
                                  semanticLabel: scene.semanticLabel,
                                  play: selected,
                                  width: stageSize,
                                  height: stageSize,
                                  onPresented: onAnimationPresented,
                                  fallback: _SceneFallback(scene: scene),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: WanpanSpacing.xs),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 30,
                        decoration: BoxDecoration(
                          color: scene.accent,
                          borderRadius: BorderRadius.circular(WanpanRadii.pill),
                        ),
                      ),
                      const SizedBox(width: WanpanSpacing.sm),
                      Expanded(
                        child: Text(
                          scene.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        '${_scenes.indexOf(scene) + 1}/${_scenes.length}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: WanpanSpacing.xs),
                  Text(
                    scene.kind == _MotionSceneKind.milestone
                        ? '${scene.brief}${_sequenceSourceCopy(milestoneSequence.source)}'
                        : scene.brief,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _sequenceSourceCopy(MilestoneGradeSequenceSource source) =>
    switch (source) {
      MilestoneGradeSequenceSource.configured => '当前为手动配置。',
      MilestoneGradeSequenceSource.currentMonth => '当前取自本月最近记录。',
      MilestoneGradeSequenceSource.fallback => '当前为无数据演示默认。',
    };

class _SceneFallback extends StatelessWidget {
  const _SceneFallback({required this.scene});

  final _MotionScene scene;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(34),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WanpanRadii.large),
        child: Image.asset(scene.fallbackAsset, fit: BoxFit.cover),
      ),
    );
  }
}

class _MilestoneSequenceButton extends StatelessWidget {
  const _MilestoneSequenceButton({required this.sequence, required this.onTap});

  final MilestoneGradeSequence sequence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      semanticLabel: '配置里程碑等级，当前 ${sequence.displayLabel}',
      borderRadius: BorderRadius.circular(WanpanRadii.pill),
      pressedScale: .97,
      enableHaptics: true,
      onTap: onTap,
      child: Container(
        key: const Key('milestone-grade-config-button'),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: WanpanColors.sunflowerSoft,
          borderRadius: BorderRadius.circular(WanpanRadii.pill),
          border: Border.all(color: WanpanColors.sunflower),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sequence.displayLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: WanpanColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.tune_rounded, size: 16, color: WanpanColors.ink),
          ],
        ),
      ),
    );
  }
}

class _MilestoneGradeEditorSheet extends StatefulWidget {
  const _MilestoneGradeEditorSheet({required this.initialGrades});

  final List<String> initialGrades;

  @override
  State<_MilestoneGradeEditorSheet> createState() =>
      _MilestoneGradeEditorSheetState();
}

class _MilestoneGradeEditorSheetState
    extends State<_MilestoneGradeEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialGrades.join(', '),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useDemoDefault() {
    setState(() {
      _controller.text = MilestoneGradeSequenceResolver.fallbackGrades.join(
        ', ',
      );
      _error = null;
    });
  }

  void _save() {
    final rawTokens = _controller.text
        .split(RegExp(r'[\s,，、>→/|_-]+'))
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    final grades = MilestoneGradeSequenceResolver.parseConfigured(
      _controller.text,
    );
    if (rawTokens.length != 3) {
      setState(() => _error = '请输入恰好 3 个等级');
      return;
    }
    if (grades.length != 3) {
      setState(() => _error = '仅支持 V0–V17，且不要重复');
      return;
    }
    Navigator.of(context).pop(grades);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 6, 20, 20 + keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('配置里程碑等级', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '输入 3 个不重复的 V 级，用逗号或箭头分隔。例如：V2, V4, V5。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('milestone-grade-config-field'),
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: '等级序列',
                hintText: 'V1, V2, V3',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('milestone-use-demo-default'),
                onPressed: _useDemoDefault,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('使用 V1 → V2 → V3'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: WanpanButton(
                    label: '取消',
                    style: WanpanButtonStyle.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: WanpanButton(
                    label: '应用并重播',
                    semanticLabel: '应用里程碑等级并重播',
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackBadge extends StatelessWidget {
  const _PlaybackBadge({
    required this.reduceMotion,
    required this.accent,
    required this.tint,
  });

  final bool reduceMotion;
  final Color accent;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(WanpanRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reduceMotion
                ? Icons.accessibility_new_rounded
                : Icons.play_arrow_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 4),
          Text(
            reduceMotion ? '减少动效 · 最终帧' : '正常播放 · 单次',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: accent, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WanpanPressable(
      semanticLabel: label,
      borderRadius: BorderRadius.circular(WanpanRadii.medium),
      enableHaptics: true,
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          borderRadius: BorderRadius.circular(WanpanRadii.medium),
          border: Border.all(color: WanpanColors.border),
        ),
        child: Icon(icon, color: WanpanColors.ink, size: 22),
      ),
    );
  }
}
