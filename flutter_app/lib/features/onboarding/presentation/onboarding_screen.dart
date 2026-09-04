import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/wanpan_theme.dart';
import '../../../shared/app_assets.dart';
import '../../../shared/motion/wanpan_motion.dart';
import '../../../shared/widgets/wanpan_mascot.dart';
import '../../../shared/widgets/wanpan_pressable.dart';
import '../application/onboarding_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.controller,
    required this.onFinished,
    required this.onSkipped,
    required this.onExit,
    super.key,
  });

  final OnboardingController controller;
  final ValueChanged<String> onFinished;
  final VoidCallback onSkipped;
  final VoidCallback onExit;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 3;

  int _step = 0;
  bool _movingForward = true;
  bool _transitioning = false;
  bool _saving = false;
  bool _skipping = false;
  String? _error;
  final Set<OnboardingGoal> _selectedGoals = {};

  bool get _canContinue => _step < _stepCount - 1 || _selectedGoals.isNotEmpty;

  String get _finishLabel {
    if (_selectedGoals.isEmpty) return '至少选择一项';
    if (_selectedGoals.length == 1) {
      return _selectedGoals.single.buttonLabel;
    }
    return '进入主页';
  }

  void _toggleGoal(OnboardingGoal goal) {
    if (_saving) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedGoals.add(goal)) {
        _selectedGoals.remove(goal);
      }
      _error = null;
    });
  }

  Future<void> _continue() async {
    if (!_canContinue || _saving || _transitioning) return;
    if (_step < _stepCount - 1) {
      await _moveTo(_step + 1, forward: true);
      return;
    }
    await _finish();
  }

  Future<void> _back() async {
    if (_saving || _transitioning) return;
    if (_step == 0) {
      widget.onExit();
      return;
    }
    await _moveTo(_step - 1, forward: false);
  }

  Future<void> _moveTo(int step, {required bool forward}) async {
    setState(() {
      _movingForward = forward;
      _transitioning = true;
      _step = step;
      _error = null;
    });
    await Future<void>.delayed(
      WanpanMotion.duration(context, WanpanMotion.enter),
    );
    if (mounted) setState(() => _transitioning = false);
  }

  Future<void> _finish({bool skipped = false}) async {
    if (_saving || _transitioning) return;
    final selectedGoals = Set<OnboardingGoal>.of(_selectedGoals);
    if (!skipped && selectedGoals.isEmpty) return;
    final landingGoal = selectedGoals.length == 1 ? selectedGoals.single : null;

    setState(() {
      _saving = true;
      _skipping = skipped;
      _error = null;
    });
    try {
      if (skipped) {
        await widget.controller.skip();
      } else {
        await widget.controller.complete(landingGoal: landingGoal);
      }
      if (!mounted) return;
      if (skipped) {
        widget.onSkipped();
      } else {
        widget.onFinished(landingGoal?.destination ?? '/gyms');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '设置没有保存成功，请再试一次。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _skipping = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WanpanMotion.reduceMotion(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        key: const Key('onboarding-screen'),
        backgroundColor: WanpanColors.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _OnboardingHeader(
                step: _step,
                stepCount: _stepCount,
                busy: _saving || _transitioning,
                skipping: _skipping,
                onBack: _back,
                onSkip: () => _finish(skipped: true),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: WanpanMotion.duration(context, WanpanMotion.enter),
                  reverseDuration: WanpanMotion.duration(
                    context,
                    WanpanMotion.exit,
                  ),
                  switchInCurve: WanpanMotion.curve(context),
                  switchOutCurve: WanpanMotion.curve(context),
                  transitionBuilder: (child, animation) {
                    final childStep = (child.key as ValueKey<int>).value;
                    final entering = childStep == _step;
                    final direction = _movingForward ? 1.0 : -1.0;
                    final begin = reduceMotion
                        ? Offset.zero
                        : Offset((entering ? .055 : -.055) * direction, 0);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: begin,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => const _FeatureStep(
                        asset: AppAssets.mascotLoading,
                        mascotLabel: '黑猫趴在岩点上查看线路图',
                        eyebrow: '发现线路',
                        title: '先找到今天想爬的线',
                        description: '从城市和岩馆出发，看看最近换了哪些线，再按 V 级挑一个想试的。',
                        features: [
                          _FeatureItem(
                            icon: Icons.location_on_rounded,
                            accent: WanpanColors.sky,
                            title: '按城市和岩馆浏览',
                          ),
                          _FeatureItem(
                            icon: Icons.tune_rounded,
                            accent: WanpanColors.grape,
                            title: '查看换线周期与 V 级',
                          ),
                        ],
                      ),
                      1 => const _FeatureStep(
                        asset: AppAssets.mascotCelebrate,
                        mascotLabel: '黑猫在岩壁上庆祝完攀',
                        eyebrow: '记录成长',
                        title: '把每一次上墙都记下来',
                        description: '完攀、尝试和视频会一起留在日记里，回头就能看见自己的变化。',
                        features: [
                          _FeatureItem(
                            icon: Icons.task_alt_rounded,
                            accent: WanpanColors.coral,
                            title: '记录完攀与尝试次数',
                          ),
                          _FeatureItem(
                            icon: Icons.calendar_month_rounded,
                            accent: WanpanColors.sunflower,
                            title: '在攀岩日历回看成长',
                          ),
                        ],
                      ),
                      _ => _GoalStep(
                        selected: _selectedGoals,
                        enabled: !_saving,
                        onToggled: _toggleGoal,
                      ),
                    },
                  ),
                ),
              ),
              _OnboardingAction(
                isLastStep: _step == _stepCount - 1,
                enabled: _canContinue && !_saving && !_transitioning,
                loading: _saving && !_skipping,
                finishLabel: _finishLabel,
                error: _error,
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.step,
    required this.stepCount,
    required this.busy,
    required this.skipping,
    required this.onBack,
    required this.onSkip,
  });

  final int step;
  final int stepCount;
  final bool busy;
  final bool skipping;
  final VoidCallback onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
    child: Row(
      children: [
        IconButton(
          key: const Key('onboarding-back'),
          onPressed: busy ? null : onBack,
          tooltip: step == 0 ? '返回欢迎页' : '上一步',
          icon: const Icon(Icons.arrow_back_rounded),
          color: WanpanColors.inkSecondary,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            key: const Key('onboarding-progress'),
            excludeSemantics: true,
            label: '引导进度',
            value: '第 ${step + 1} 步，共 $stepCount 步',
            child: _SegmentedOnboardingProgress(
              step: step,
              stepCount: stepCount,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ExcludeSemantics(
          child: Text(
            '${step + 1}/$stepCount',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: WanpanColors.ink),
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 64,
          child: onSkip == null
              ? const SizedBox.shrink()
              : Tooltip(
                  message: '跳过引导，继续前往',
                  child: TextButton(
                    key: const Key('onboarding-skip'),
                    onPressed: busy ? null : onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: WanpanColors.ink,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                    ),
                    child: Semantics(
                      liveRegion: skipping,
                      label: skipping ? '正在跳过引导' : '跳过',
                      child: ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (skipping) ...[
                              const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: WanpanColors.ink,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            const Text(
                              '跳过',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _SegmentedOnboardingProgress extends StatelessWidget {
  const _SegmentedOnboardingProgress({
    required this.step,
    required this.stepCount,
  });

  final int step;
  final int stepCount;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < stepCount; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: AnimatedContainer(
            key: Key('onboarding-progress-segment-$index'),
            duration: WanpanMotion.duration(context, WanpanMotion.progress),
            curve: WanpanMotion.curve(context),
            height: 9,
            decoration: BoxDecoration(
              color: index <= step
                  ? WanpanColors.coralStrong
                  : WanpanColors.surfaceMuted,
              borderRadius: BorderRadius.circular(WanpanRadii.pill),
            ),
          ),
        ),
      ],
    ],
  );
}

class _FeatureStep extends StatelessWidget {
  const _FeatureStep({
    required this.asset,
    required this.mascotLabel,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.features,
  });

  final String asset;
  final String mascotLabel;
  final String eyebrow;
  final String title;
  final String description;
  final List<_FeatureItem> features;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 500;
      final mascotSize = compact ? 132.0 : 184.0;
      return SingleChildScrollView(
        key: PageStorageKey(asset),
        padding: EdgeInsets.fromLTRB(
          WanpanSpacing.page,
          compact ? 4 : 14,
          WanpanSpacing.page,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Semantics(
                    image: true,
                    label: mascotLabel,
                    child: ExcludeSemantics(
                      child: WanpanMascot(
                        asset: asset,
                        width: mascotSize,
                        height: mascotSize,
                        radius: compact ? 24 : 32,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 20),
                Text(
                  eyebrow,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: WanpanColors.ink, letterSpacing: 1.1),
                ),
                const SizedBox(height: 7),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: WanpanColors.ink),
                ),
                SizedBox(height: compact ? 16 : 24),
                Text(
                  '你可以',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: WanpanColors.inkSecondary),
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < features.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  _FeatureTile(item: features[index]),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _FeatureItem {
  const _FeatureItem({
    required this.icon,
    required this.accent,
    required this.title,
  });

  final IconData icon;
  final Color accent;
  final String title;
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.item});

  final _FeatureItem item;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '功能说明：${item.title}',
    child: ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: WanpanColors.surfaceSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: item.accent, size: 24),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({
    required this.selected,
    required this.enabled,
    required this.onToggled,
  });

  final Set<OnboardingGoal> selected;
  final bool enabled;
  final ValueChanged<OnboardingGoal> onToggled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 360;
      final mascotSize = compact ? 88.0 : 108.0;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          WanpanSpacing.page,
          compact ? 2 : 10,
          WanpanSpacing.page,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Semantics(
                      image: true,
                      label: '黑猫教练挥手邀请你选择第一站',
                      child: ExcludeSemantics(
                        child: WanpanMascot(
                          asset: AppAssets.mascotWelcome,
                          width: mascotSize,
                          height: mascotSize,
                          radius: 24,
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 16),
                    Expanded(
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: const _SpeechBubble(text: '你想先从哪里开始？'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 12 : 18),
                Text(
                  '可多选：单选直达所选页面，多选进入主页。游客可先浏览，打卡时再登录。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: WanpanColors.ink),
                ),
                SizedBox(height: compact ? 12 : 16),
                for (final goal in OnboardingGoal.values) ...[
                  _GoalCard(
                    key: Key('onboarding-goal-${goal.name}'),
                    goal: goal,
                    selected: selected.contains(goal),
                    enabled: enabled,
                    onTap: () => onToggled(goal),
                  ),
                  if (goal != OnboardingGoal.values.last)
                    const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: -7,
        top: 30,
        child: Transform.rotate(
          angle: .785398,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: WanpanColors.surface,
              border: Border.all(color: WanpanColors.border, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: WanpanColors.surface,
          border: Border.all(color: WanpanColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontSize: 19, height: 1.28),
        ),
      ),
    ],
  );
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final OnboardingGoal goal;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    enabled: enabled,
    checked: selected,
    label: '${goal.title}，${goal.subtitle}',
    hint: selected ? '双击取消选择' : '双击选择',
    onTap: enabled ? onTap : null,
    child: ExcludeSemantics(
      child: WanpanPressable(
        onTap: enabled ? onTap : null,
        enableHaptics: false,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: WanpanMotion.duration(context, WanpanMotion.selection),
          curve: WanpanMotion.curve(context),
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: selected ? WanpanColors.coralSoft : WanpanColors.surface,
            border: Border.all(
              color: selected ? WanpanColors.coralStrong : WanpanColors.border,
              width: selected ? 2 : 1.2,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: goal.accent.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Icon(goal.icon, color: goal.accent, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      goal.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goal.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.35,
                        color: selected
                            ? WanpanColors.ink
                            : WanpanColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: WanpanMotion.duration(
                  context,
                  WanpanMotion.selection,
                ),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected
                      ? WanpanColors.coralStrong
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? WanpanColors.coralStrong
                        : WanpanColors.borderStrong,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OnboardingAction extends StatelessWidget {
  const _OnboardingAction({
    required this.isLastStep,
    required this.enabled,
    required this.loading,
    required this.finishLabel,
    required this.error,
    required this.onPressed,
  });

  final bool isLastStep;
  final bool enabled;
  final bool loading;
  final String finishLabel;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: WanpanColors.surface,
      border: Border(top: BorderSide(color: WanpanColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  Semantics(
                    key: const Key('onboarding-error'),
                    liveRegion: true,
                    child: Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: WanpanColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                WanpanButton(
                  key: Key(
                    isLastStep ? 'onboarding-finish' : 'onboarding-continue',
                  ),
                  label: isLastStep ? finishLabel : '继续',
                  loading: loading,
                  onPressed: enabled ? onPressed : null,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

extension on OnboardingGoal {
  String get title => switch (this) {
    OnboardingGoal.findGyms => '找附近岩馆',
    OnboardingGoal.checkInRoute => '找线路打卡',
    OnboardingGoal.browseFeed => '逛逛广场',
    OnboardingGoal.viewRanking => '看看热门线路',
  };

  String get subtitle => switch (this) {
    OnboardingGoal.findGyms => '从城市和品牌找到想去的门店',
    OnboardingGoal.checkInRoute => '选一条线路，记录完攀和尝试',
    OnboardingGoal.browseFeed => '看看岩友最近都在爬什么',
    OnboardingGoal.viewRanking => '看看近期完攀和点赞多的线路',
  };

  IconData get icon => switch (this) {
    OnboardingGoal.findGyms => Icons.location_on_rounded,
    OnboardingGoal.checkInRoute => Icons.task_alt_rounded,
    OnboardingGoal.browseFeed => Icons.forum_rounded,
    OnboardingGoal.viewRanking => Icons.emoji_events_rounded,
  };

  Color get accent => switch (this) {
    OnboardingGoal.findGyms => WanpanColors.sky,
    OnboardingGoal.checkInRoute => WanpanColors.coral,
    OnboardingGoal.browseFeed => WanpanColors.grape,
    OnboardingGoal.viewRanking => WanpanColors.sunflower,
  };

  String get destination => switch (this) {
    OnboardingGoal.findGyms => '/gyms',
    OnboardingGoal.checkInRoute => '/routes/pick',
    OnboardingGoal.browseFeed => '/feed',
    OnboardingGoal.viewRanking => '/ranking?tab=routes',
  };

  String get buttonLabel => switch (this) {
    OnboardingGoal.findGyms => '去找岩馆',
    OnboardingGoal.checkInRoute => '去找线路',
    OnboardingGoal.browseFeed => '去逛广场',
    OnboardingGoal.viewRanking => '去看热门线路',
  };
}
