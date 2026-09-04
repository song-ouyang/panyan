import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/wanpan_theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/app_assets.dart';
import '../../../shared/motion/wanpan_motion.dart';
import '../../../shared/widgets/wanpan_pressable.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';
import '../data/native_auth_service.dart';
import '../domain/auth_return_path.dart';

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
  String? _retryProvider;
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
      _retryProvider = null;
      _inlineIsError = true;
    });
    try {
      await authenticate();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (!navigateAfterSuccess) return;
      final destination = safeAuthReturnTo(widget.returnTo);
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
        _retryProvider = provider;
        _inlineIsError = true;
      });
      HapticFeedback.heavyImpact();
    } on ApiException catch (error) {
      if (error.isUnauthorized) await widget.session.handleUnauthorized();
      if (!mounted) return;
      setState(() {
        _inlineMessage = _friendlyApiMessage(provider, error);
        _retryProvider = provider;
        _inlineIsError = true;
      });
      HapticFeedback.heavyImpact();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _inlineMessage = '登录没有完成，请稍后重试。';
        _retryProvider = provider;
        _inlineIsError = true;
      });
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  String _friendlyApiMessage(String provider, ApiException error) {
    final normalizedCode = error.code.toUpperCase();
    final normalizedMessage = error.message.toLowerCase();
    final isValidationFailure =
        normalizedCode.contains('VALIDATION') ||
        error.issues.isNotEmpty ||
        normalizedMessage.contains('zod') ||
        normalizedMessage.contains('invalid input');
    if (isValidationFailure && provider.startsWith('sms-')) {
      return '手机号或验证码格式不正确，请检查后重试。';
    }
    if (isValidationFailure) return '登录信息格式不正确，请重试。';

    return switch (error.statusCode) {
      400 || 422 => '提交的登录信息不正确，请检查后重试。',
      401 when provider == 'sms-login' => '验证码错误或已失效，请重新获取。',
      401 => '登录状态已失效，请重新登录。',
      403 => '当前登录方式暂不可用，请稍后重试。',
      404 when provider.startsWith('sms-') => '当前服务器版本暂不支持手机号登录，请稍后重试。',
      404 => '当前服务器版本暂不支持此登录方式，请稍后重试。',
      429 => '请求太频繁，请稍后再试。',
      500 => '登录服务处理失败，请稍后重试。',
      502 || 503 || 504 when provider == 'sms-send' => '短信服务暂时不可用，请稍后重试。',
      502 || 503 || 504 => '登录服务暂时不可用，请稍后重试。',
      null when normalizedMessage.contains('超时') => '连接登录服务超时，请检查网络后重试。',
      null => '网络连接失败，请检查网络后重试。',
      _ => '登录没有完成，请稍后重试。',
    };
  }

  Future<void> _retryLastFailure() async {
    final provider = _retryProvider;
    switch (provider) {
      case 'sms-send':
        return _sendSmsCode();
      case 'sms-login':
        return _smsLogin();
      case 'apple':
        return _appleLogin();
      case 'development':
        return _developmentLogin();
      default:
        return;
    }
  }

  String? _validatedPhone() {
    final phone = _phoneController.text.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() {
        _inlineMessage = '请输入正确的 11 位中国大陆手机号。';
        _retryProvider = null;
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
      _retryProvider = null;
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
        _retryProvider = null;
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
        _retryProvider = null;
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

  Future<void> _openLegalPage(String path) async {
    final opened = await launchUrl(
      Uri.parse('https://panyan-api.gblh.cloud$path'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() {
        _inlineMessage = '暂时无法打开网页，请稍后再试。';
        _retryProvider = null;
        _inlineIsError = true;
      });
    }
  }

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
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 36),
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
                    RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: SizedBox(
                          height: 326,
                          width: double.infinity,
                          child: Image.asset(
                            AppAssets.loginGardenHero,
                            cacheWidth: 1200,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '每一次上墙都有记录',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 26, letterSpacing: -.6),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 62,
                      child: TextField(
                        key: const Key('sms-phone'),
                        controller: _phoneController,
                        enabled: !_busy,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 11,
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: const InputDecoration(
                          hintText: '手机号',
                          prefixIcon: Icon(Icons.phone_iphone_rounded),
                          counterText: '',
                          fillColor: WanpanColors.surface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 62,
                      decoration: BoxDecoration(
                        color: WanpanColors.surface,
                        borderRadius: BorderRadius.circular(WanpanRadii.medium),
                        border: Border.all(color: WanpanColors.border),
                      ),
                      child: Row(
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
                              style: Theme.of(context).textTheme.bodyLarge,
                              decoration: const InputDecoration(
                                hintText: '验证码',
                                counterText: '',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const Key('sms-send-code'),
                            onPressed: _busy || _secondsUntilResend > 0
                                ? null
                                : _sendSmsCode,
                            style: TextButton.styleFrom(
                              foregroundColor: WanpanColors.coral,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
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
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '我已阅读并同意',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                                TextButton(
                                  key: const Key('open-terms'),
                                  onPressed: () => _openLegalPage('/terms'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                  child: const Text('《用户协议》'),
                                ),
                                Text(
                                  '与',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                                TextButton(
                                  key: const Key('open-privacy'),
                                  onPressed: () => _openLegalPage('/privacy'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                  child: const Text('《隐私政策》'),
                                ),
                                Text(
                                  '。',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
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
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _inlineMessage!,
                                      textAlign: _retryProvider == null
                                          ? TextAlign.center
                                          : TextAlign.start,
                                      style: TextStyle(
                                        color: _inlineIsError
                                            ? WanpanColors.danger
                                            : const Color(0xFF2E7D4F),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (_inlineIsError &&
                                      _retryProvider != null) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      key: const Key('login-retry'),
                                      onPressed: _busy
                                          ? null
                                          : _retryLastFailure,
                                      style: TextButton.styleFrom(
                                        foregroundColor: WanpanColors.coral,
                                        minimumSize: const Size(48, 44),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: const Text('重试'),
                                    ),
                                  ],
                                ],
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
