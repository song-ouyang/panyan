import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/wanpan_theme.dart';
import '../../features/auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_pressable.dart';

class StartupSplashScreen extends StatelessWidget {
  const StartupSplashScreen({
    required this.progress,
    required this.failed,
    super.key,
    this.onRetry,
  });

  final double progress;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _SplashFrame(
    action: failed
        ? Column(
            key: const ValueKey('startup-failed'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '启动没有完成，请再试一次',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: WanpanColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              WanpanButton(label: '重新加载', onPressed: onRetry),
            ],
          )
        : _StartupProgress(
            key: const ValueKey('bootstrap-progress'),
            progress: progress,
          ),
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    required this.session,
    required this.onContinue,
    super.key,
  });

  final SessionController session;
  final VoidCallback onContinue;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _ready = false;
  bool _finishing = false;
  Timer? _readyTimer;

  @override
  void initState() {
    super.initState();
    _ready = !widget.session.isInitializing;
    widget.session.addListener(_handleSessionChanged);
  }

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session.removeListener(_handleSessionChanged);
    widget.session.addListener(_handleSessionChanged);
    _readyTimer?.cancel();
    _finishing = false;
    _ready = !widget.session.isInitializing;
  }

  void _handleSessionChanged() {
    if (widget.session.isInitializing || _ready || _finishing) return;
    _finishing = true;
    setState(() {});
    final delay = WanpanMotion.duration(context, WanpanMotion.progress);
    _readyTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _finishing = false;
      });
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    widget.session.removeListener(_handleSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.session.isInitializing ? .86 : 1.0;
    return _SplashFrame(
      action: AnimatedSwitcher(
        duration: WanpanMotion.duration(context, WanpanMotion.enter),
        reverseDuration: WanpanMotion.duration(context, WanpanMotion.exit),
        switchInCurve: WanpanMotion.curve(context),
        switchOutCurve: WanpanMotion.curve(context),
        child: _ready
            ? WanpanButton(
                key: const ValueKey('splash-continue'),
                label: '进入完攀日记',
                onPressed: widget.onContinue,
              )
            : _StartupProgress(
                key: const ValueKey('session-progress'),
                progress: progress,
              ),
      ),
    );
  }
}

class _SplashFrame extends StatelessWidget {
  const _SplashFrame({required this.action});

  static const _background = Color(0xFFFFF8EF);

  final Widget action;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
    child: Scaffold(
      backgroundColor: _background,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 650;
          final actionWidth = math.min(
            constraints.maxWidth - (compact ? 32 : 40),
            560.0,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              SizedBox.expand(
                key: const Key('splash-hero'),
                child: Image.asset(
                  AppAssets.launchBackground,
                  key: const Key('splash-background'),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const _SplashFallback(),
                ),
              ),
              const IgnorePointer(child: _BottomLegibilityGradient()),
              SafeArea(
                top: false,
                minimum: EdgeInsets.only(
                  left: compact ? 16 : 20,
                  right: compact ? 16 : 20,
                  bottom: compact ? 12 : 20,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    key: const Key('splash-actions'),
                    width: actionWidth,
                    child: action,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _StartupProgress extends StatelessWidget {
  const _StartupProgress({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final target = progress.clamp(0.0, 1.0);
    return Semantics(
      label: '启动进度',
      value: '${(target * 100).round()}%',
      liveRegion: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        duration: WanpanMotion.duration(context, WanpanMotion.progress),
        curve: WanpanMotion.curve(context),
        builder: (context, value, _) => ClipRRect(
          key: const Key('splash-progress'),
          borderRadius: BorderRadius.circular(WanpanRadii.pill),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: const Color(0xE6FFFDF7),
            color: WanpanColors.coral,
          ),
        ),
      ),
    );
  }
}

class _BottomLegibilityGradient extends StatelessWidget {
  const _BottomLegibilityGradient();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Color(0x24FFF8EF),
          Color(0xB8FFF8EF),
        ],
        stops: [0, .68, .84, 1],
      ),
    ),
  );
}

class _SplashFallback extends StatelessWidget {
  const _SplashFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: Color(0xFFFFF8EF)),
    child: Center(
      child: Icon(
        Icons.landscape_rounded,
        size: 132,
        color: WanpanColors.coral,
      ),
    ),
  );
}
