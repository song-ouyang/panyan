import 'dart:async';

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
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  Timer? _countdownTimer;
  DateTime? _resendAvailableAt;
  String? _busyProvider;
  String? _inlineMessage;
  var _inlineIsError = true;
  var _secondsUntilResend = 0;
  var _agreedToTerms = false;

  bool get _busy => _busyProvider != null;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(
    String provider,
    Future<void> Function() authenticate, {
    bool navigateAfterSuccess = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busyProvider = provider;
      _inlineMessage = null;
      _inlineIsError = true;
    });
    try {
      await authenticate();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (!navigateAfterSuccess) return;
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
      setState(() {
        _inlineMessage = error.message;
        _inlineIsError = true;
      });
      HapticFeedback.heavyImpact();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineMessage = switch (error.statusCode) {
          404 => '登录服务暂未就绪，请稍后重试。',
          429 => '请求太频繁，请稍后再试。',
          _ => error.message,
        };
        _inlineIsError = true;
      });
      HapticFeedback.heavyImpact();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _inlineMessage = '登录没有完成，请稍后重试。';
        _inlineIsError = true;
      });
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  String _safeReturnTo(String value) =>
      value.startsWith('/') && !value.startsWith('/login') ? value : '/gyms';

  String? _validatedPhone() {
    final phone = _phoneController.text.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() {
        _inlineMessage = '请输入正确的 11 位中国大陆手机号。';
        _inlineIsError = true;
      });
      return null;
    }
    return phone;
  }

  bool _checkTerms() {
    if (_agreedToTerms) return true;
    setState(() {
      _inlineMessage = '请先阅读并同意用户协议与隐私政策。';
      _inlineIsError = true;
    });
    return false;
  }

  Future<void> _sendSmsCode() async {
    if (_busy || _secondsUntilResend > 0 || !_checkTerms()) return;
    final phone = _validatedPhone();
    if (phone == null) return;
    await _run('sms-send', () async {
      await widget.repository.sendSmsCode(phone: phone);
      if (!mounted) return;
      setState(() {
        _secondsUntilResend = 60;
        _resendAvailableAt = DateTime.now().add(const Duration(seconds: 60));
        _inlineMessage = '验证码已发送，请注意查收。';
        _inlineIsError = false;
      });
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final remainingMilliseconds =
            _resendAvailableAt?.difference(DateTime.now()).inMilliseconds ?? 0;
        final remaining = (remainingMilliseconds / 1000).ceil();
        if (!mounted || remaining <= 0) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _secondsUntilResend = 0;
              _resendAvailableAt = null;
            });
          }
          return;
        }
        setState(() => _secondsUntilResend = remaining);
      });
    }, navigateAfterSuccess: false);
  }

  Future<void> _smsLogin() async {
    if (_busy || !_checkTerms()) return;
    final phone = _validatedPhone();
    if (phone == null) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _inlineMessage = '请输入 6 位验证码。';
        _inlineIsError = true;
      });
      return;
    }
    await _run('sms-login', () async {
      final authSession = await widget.repository.signInWithSms(
        phone: phone,
        code: code,
      );
      await widget.session.acceptSession(authSession);
    });
  }

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
                      '使用手机号验证码登录。打卡、发布动态、投稿线路和添加岩友时才需要登录，岩馆仍可以直接浏览。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      key: const Key('sms-phone'),
                      controller: _phoneController,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 11,
                      decoration: const InputDecoration(
                        labelText: '手机号',
                        hintText: '请输入 11 位手机号',
                        prefixIcon: Icon(Icons.phone_iphone_rounded),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('sms-code'),
                            controller: _codeController,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '验证码',
                              hintText: '6 位验证码',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          key: const Key('sms-send-code'),
                          onPressed: _busy || _secondsUntilResend > 0
                              ? null
                              : _sendSmsCode,
                          child: Text(
                            _busyProvider == 'sms-send'
                                ? '发送中…'
                                : _secondsUntilResend > 0
                                ? '${_secondsUntilResend}s 后重发'
                                : '获取验证码',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _agreedToTerms,
                          onChanged: _busy
                              ? null
                              : (value) => setState(
                                  () => _agreedToTerms = value ?? false,
                                ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              '我已阅读并同意《用户协议》与《隐私政策》。',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                    WanpanButton(
                      key: const Key('sms-login'),
                      label: '验证码登录',
                      loading: _busyProvider == 'sms-login',
                      onPressed: _busy ? null : _smsLogin,
                      icon: const Icon(Icons.login_rounded),
                    ),
                    if (widget.nativeAuth.canAttemptApple) ...[
                      const SizedBox(height: 20),
                      Text(
                        '其他登录方式',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
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
                              key: Key(
                                _inlineIsError
                                    ? 'login-error'
                                    : 'login-success',
                              ),
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: _inlineIsError
                                    ? const Color(0xFFFFF1EF)
                                    : const Color(0xFFEAF8EF),
                                borderRadius: BorderRadius.circular(
                                  WanpanRadii.small,
                                ),
                              ),
                              child: Text(
                                _inlineMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _inlineIsError
                                      ? WanpanColors.danger
                                      : const Color(0xFF2E7D4F),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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
