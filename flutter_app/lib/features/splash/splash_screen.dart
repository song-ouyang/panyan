import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../../features/auth/application/session_controller.dart';
import '../../shared/app_assets.dart';
import '../../shared/motion/wanpan_motion.dart';
import '../../shared/widgets/wanpan_pressable.dart';

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
  static const _heroAspectRatio = 750 / 1038;
  static const _background = Color(0xFFFFF8EF);

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _background,
    body: ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final preparing = widget.session.isInitializing;
        return ColoredBox(
          color: _background,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 650;
                final heroMaxWidth = math.min(constraints.maxWidth, 620.0);
                final heroMaxHeight =
                    constraints.maxHeight * (compact ? .76 : .72);
                final heroWidth = math.min(
                  heroMaxWidth,
                  heroMaxHeight * _heroAspectRatio,
                );
                final actionWidth = math.min(
                  constraints.maxWidth - (compact ? 32 : 40),
                  560.0,
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        key: const Key('splash-hero'),
                        width: heroWidth,
                        height: heroWidth / _heroAspectRatio,
                        child: Image.asset(
                          AppAssets.launchHero,
                          fit: BoxFit.contain,
                          alignment: Alignment.topCenter,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const _SplashFallback(),
                        ),
                      ),
                    ),
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              Color(0xF2FFF8EF),
                              _background,
                            ],
                            stops: [0, .57, .78, 1],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        key: const Key('splash-actions'),
                        width: actionWidth,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: compact ? 12 : 20),
                          child: AnimatedSlide(
                            offset:
                                _visible && !WanpanMotion.reduceMotion(context)
                                ? Offset.zero
                                : const Offset(0, .06),
                            duration: WanpanMotion.duration(
                              context,
                              WanpanMotion.enter,
                            ),
                            curve: WanpanMotion.curve(context),
                            child: AnimatedOpacity(
                              opacity: _visible ? 1 : 0,
                              duration: WanpanMotion.duration(
                                context,
                                WanpanMotion.exit,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '记录每一次上墙，看见每一步成长',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: WanpanColors.inkSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  SizedBox(height: compact ? 14 : 20),
                                  WanpanButton(
                                    label: preparing ? '正在准备你的攀岩日记…' : '进入完攀日记',
                                    loading: preparing,
                                    onPressed: preparing
                                        ? null
                                        : widget.onContinue,
                                  ),
                                ],
                              ),
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
      },
    ),
  );
}

class _SplashFallback extends StatelessWidget {
  const _SplashFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [WanpanColors.coralSoft, WanpanColors.goldSoft, Colors.white],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.landscape_rounded,
        size: 132,
        color: WanpanColors.coral,
      ),
    ),
  );
}
