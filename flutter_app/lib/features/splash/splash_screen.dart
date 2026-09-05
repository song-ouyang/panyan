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
        : _StartupProgress(progress: progress),
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
    return _SplashFrame(
      action: AnimatedSwitcher(
        duration: WanpanMotion.duration(context, WanpanMotion.enter),
        reverseDuration: WanpanMotion.duration(context, WanpanMotion.exit),
        switchInCurve: WanpanMotion.curve(context),
        switchOutCurve: WanpanMotion.curve(context),
        child: _ready
            ? WanpanButton(
                key: const ValueKey('splash-continue'),
                label: '立即开爬',
                onPressed: widget.onContinue,
              )
            : _StartupProgress(
                key: const ValueKey('session-progress'),
                progress: widget.session.isInitializing ? .72 : 1,
              ),
      ),
    );
  }
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
      child: SizedBox(
        height: 66,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: math.min(.12, target), end: target),
            duration: WanpanMotion.duration(context, WanpanMotion.progress),
            curve: WanpanMotion.curve(context),
            builder: (context, value, _) => ClipRRect(
              key: const Key('splash-progress'),
              borderRadius: BorderRadius.circular(WanpanRadii.pill),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: WanpanColors.border,
                color: WanpanColors.coral,
                // Keep the bar identical to the native launch placeholder.
                stopIndicatorRadius: 0,
                trackGap: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashFrame extends StatelessWidget {
  const _SplashFrame({required this.action});

  final Widget action;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
    child: Scaffold(
      backgroundColor: WanpanColors.canvas,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 650;
          final gutter = compact ? 20.0 : 28.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(
                key: Key('splash-background'),
                color: WanpanColors.canvas,
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    compact ? 12 : 28,
                    gutter,
                    compact ? 12 : 20,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '今天也去\n上墙吧！',
                            style: TextStyle(
                              color: WanpanColors.catBlack,
                              fontSize: compact ? 36 : 50,
                              fontWeight: FontWeight.w900,
                              height: 1.12,
                              letterSpacing: -1.2,
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          Text(
                            '找条喜欢的线路，\n记录一次新完攀',
                            style: TextStyle(
                              color: WanpanColors.ink,
                              fontSize: compact ? 15 : 18,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                          SizedBox(height: compact ? 8 : 16),
                          const Expanded(child: _SplashIllustration()),
                          SizedBox(height: compact ? 12 : 24),
                          ConstrainedBox(
                            key: const Key('splash-actions'),
                            constraints: const BoxConstraints(minHeight: 66),
                            child: action,
                          ),
                        ],
                      ),
                    ),
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

class _SplashIllustration extends StatelessWidget {
  const _SplashIllustration();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const aspectRatio = 1230 / 1278;
      final width = math.min(
        constraints.maxWidth,
        constraints.maxHeight * aspectRatio,
      );
      final height = width / aspectRatio;

      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  AppAssets.homeHeroCat,
                  key: const Key('splash-hero'),
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                ),
              ),
              Positioned(
                top: height * .045,
                right: 8,
                child: Transform.rotate(
                  angle: -.065,
                  child: CustomPaint(
                    painter: const _SpeechBubblePainter(),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(17, 10, 17, 19),
                      child: Text(
                        '出发喵！',
                        style: TextStyle(
                          color: WanpanColors.catBlack,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SpeechBubblePainter extends CustomPainter {
  const _SpeechBubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - 9;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, bottom - 1),
          const Radius.circular(22),
        ),
      );
    final tail = Path()
      ..moveTo(24, bottom - 3)
      ..lineTo(18, size.height - 1)
      ..quadraticBezierTo(31, size.height - 3, 39, bottom - 3)
      ..close();
    final bubble = Path.combine(PathOperation.union, body, tail);
    canvas.drawPath(bubble, Paint()..color = WanpanColors.surface);
    canvas.drawPath(
      bubble,
      Paint()
        ..color = WanpanColors.catBlack
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SpeechBubblePainter oldDelegate) => false;
}
