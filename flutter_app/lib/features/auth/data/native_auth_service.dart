import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fluwx/fluwx.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/app_config.dart';
import '../domain/auth_session.dart';
import 'auth_repository.dart';

class AuthFlowException implements Exception {
  const AuthFlowException(this.message, {this.canceled = false});

  final String message;
  final bool canceled;

  @override
  String toString() => message;
}

class NativeAuthService {
  NativeAuthService({required this.config, Fluwx? fluwx})
    : _fluwx = fluwx ?? Fluwx();

  final AppConfig config;
  final Fluwx _fluwx;
  Future<bool>? _wechatRegistration;

  bool get canAttemptWechat => config.hasWechatMobileConfig;
  bool get canAttemptApple => Platform.isIOS || Platform.isMacOS;

  String get wechatConfigurationMessage =>
      '微信登录还需配置移动应用 AppID 和 Universal Link。';

  Future<AuthSession> signInWithWechat(AuthRepository repository) async {
    final code = await _requestWechatCode();
    return repository.signInWithMobileWechatCode(code);
  }

  Future<AuthSession> signInWithApple(AuthRepository repository) async {
    if (!canAttemptApple) {
      throw const AuthFlowException('Apple 登录仅可在 Apple 设备上使用。');
    }
    final available = await SignInWithApple.isAvailable();
    if (!available) {
      throw const AuthFlowException('当前设备暂不支持 Apple 登录。');
    }

    final rawNonce = _randomToken(32);
    final nonceHash = sha256.convert(utf8.encode(rawNonce)).toString();
    final state = _randomToken(24);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonceHash,
        state: state,
      );
      if (credential.state != state) {
        throw const AuthFlowException('Apple 登录状态校验失败，请重试。');
      }
      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw const AuthFlowException('Apple 未返回可验证的登录凭证。');
      }
      return await repository.signInWithApple(
        identityToken: identityToken,
        rawNonce: rawNonce,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AuthFlowException('已取消 Apple 登录。', canceled: true);
      }
      throw AuthFlowException('Apple 登录没有完成：${error.message}');
    }
  }

  Future<String> _requestWechatCode() async {
    if (!config.hasWechatMobileConfig) {
      throw AuthFlowException(wechatConfigurationMessage);
    }
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw const AuthFlowException('微信登录需要在 iOS 或 Android 真机上使用。');
    }
    final registered = await (_wechatRegistration ??= _fluwx.registerApi(
      appId: config.wechatMobileAppId,
      universalLink: config.wechatUniversalLink,
    ));
    if (!registered) {
      _wechatRegistration = null;
      throw const AuthFlowException(
        '微信 SDK 注册失败，请检查 AppID、Universal Link 和应用签名。',
      );
    }
    if (!await _fluwx.isWeChatInstalled) {
      throw const AuthFlowException('未检测到微信，请安装后重试。');
    }

    final state = _randomToken(24);
    final completer = Completer<String>();
    late FluwxCancelable subscription;
    subscription = _fluwx.addSubscriber((response) {
      if (response is! WeChatAuthResponse || response.state != state) return;
      if (response.isSuccessful && response.code?.isNotEmpty == true) {
        completer.complete(response.code!);
      } else if (response.errCode == -2) {
        completer.completeError(
          const AuthFlowException('已取消微信登录。', canceled: true),
        );
      } else {
        completer.completeError(
          AuthFlowException(
            response.errStr?.trim().isNotEmpty == true
                ? response.errStr!
                : '微信授权没有完成，请重试。',
          ),
        );
      }
    });

    try {
      final sent = await _fluwx.authBy(
        which: NormalAuth(scope: 'snsapi_userinfo', state: state),
      );
      if (!sent) {
        throw const AuthFlowException('无法打开微信授权，请检查应用配置。');
      }
      return await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw const AuthFlowException('微信授权已超时，请重试。'),
      );
    } finally {
      subscription.cancel();
    }
  }

  String _randomToken(int byteLength) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
