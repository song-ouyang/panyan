import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../app/wanpan_theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/app_assets.dart';
import '../../../shared/motion/wanpan_motion.dart';
import '../../../shared/widgets/wanpan_pressable.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';
import '../data/native_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.session,
    required this.repository,
    required this.nativeAuth,
    required this.returnTo,
    super.key,
  });

  final SessionController session;
  final AuthRepository repository;
  final NativeAuthService nativeAuth;
  final String returnTo;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _busyProvider;
  String? _inlineMessage;

  bool get _busy => _busyProvider != null;

  Future<void> _run(
    String provider,
    Future<void> Function() authenticate,
  ) async {
    if (_busy) return;
    setState(() {
      _busyProvider = provider;
      _inlineMessage = null;
    });
    try {
      await authenticate();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final destination = _safeReturnTo(widget.returnTo);
      if (widget.session.profileNeedsCompletion) {
        context.go(
          Uri(
            path: '/profile/setup',
            queryParameters: {'from': destination},
          ).toString(),
        );
      } else {
        context.go(destination);
      }
    } on AuthFlowException catch (error) {
      if (!mounted || error.canceled) return;
      setState(() => _inlineMessage = error.message);
      HapticFeedback.heavyImpact();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _inlineMessage = error.message);
      HapticFeedback.heavyImpact();
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineMessage = '登录没有完成，请稍后重试。');
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  String _safeReturnTo(String value) =>
      value.startsWith('/') && !value.startsWith('/login') ? value : '/gyms';

  Future<void> _wechatLogin() => _run('wechat', () async {
    final authSession = await widget.nativeAuth.signInWithWechat(
      widget.repository,
    );
    await widget.session.acceptSession(authSession);
  });

  Future<void> _appleLogin() => _run('apple', () async {
    final authSession = await widget.nativeAuth.signInWithApple(
      widget.repository,
    );
    await widget.session.acceptSession(authSession);
  });

  Future<void> _developmentLogin() => _run(
    'development',
    () => widget.session.signInWithDevelopmentAccount(widget.repository),
  );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WanpanMotion.reduceMotion(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回浏览',
          onPressed: _busy ? null : () => context.go('/gyms'),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('登录'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduceMotion ? 1 : .97, end: 1),
                duration: WanpanMotion.duration(context, WanpanMotion.enter),
                curve: WanpanMotion.curve(context),
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: Opacity(opacity: value, child: child),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipOval(
                        child: Image.asset(
                          AppAssets.mascotWelcome,
                          width: 116,
                          height: 116,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const CircleAvatar(
                            radius: 58,
                            backgroundColor: WanpanColors.coralSoft,
                            child: Icon(
                              Icons.pets_rounded,
                              size: 48,
                              color: WanpanColors.coral,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '登录后，每一次上墙都有记录',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '打卡、发布动态、投稿线路和添加岩友时才需要登录，岩馆仍可以直接浏览。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    WanpanButton(
                      key: const Key('wechat-login'),
                      label: '微信登录',
                      loading: _busyProvider == 'wechat',
                      onPressed: _busy ? null : _wechatLogin,
                      icon: const Icon(Icons.chat_bubble_rounded),
                    ),
                    if (!widget.nativeAuth.canAttemptWechat) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.nativeAuth.wechatConfigurationMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                    if (widget.nativeAuth.canAttemptApple) ...[
                      const SizedBox(height: 13),
                      IgnorePointer(
                        ignoring: _busy,
                        child: AnimatedOpacity(
                          opacity: _busy ? .46 : 1,
                          duration: WanpanMotion.duration(
                            context,
                            WanpanMotion.press,
                          ),
                          child: SizedBox(
                            height: 54,
                            child: SignInWithAppleButton(
                              key: const Key('apple-login'),
                              text: 'Apple 登录',
                              borderRadius: const BorderRadius.all(
                                Radius.circular(WanpanRadii.medium),
                              ),
                              onPressed: _appleLogin,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (widget.session.canUseDevelopmentLogin) ...[
                      const SizedBox(height: 13),
                      WanpanButton(
                        key: const Key('development-login'),
                        label: '开发账号登录',
                        loading: _busyProvider == 'development',
                        style: WanpanButtonStyle.secondary,
                        onPressed: _busy ? null : _developmentLogin,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '仅在 development + ENABLE_DEV_LOGIN=true 时显示',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                    AnimatedSize(
                      duration: WanpanMotion.duration(
                        context,
                        WanpanMotion.exit,
                      ),
                      child: _inlineMessage == null
                          ? const SizedBox(height: 18)
                          : Container(
                              key: const Key('login-error'),
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1EF),
                                borderRadius: BorderRadius.circular(
                                  WanpanRadii.small,
                                ),
                              ),
                              child: Text(
                                _inlineMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: WanpanColors.danger,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '登录即表示你同意《用户协议》与《隐私政策》。我们不会在客户端保存微信或 Apple 密钥。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
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
}
