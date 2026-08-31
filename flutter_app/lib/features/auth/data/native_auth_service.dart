import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
  NativeAuthService({this.appleLoginEnabled = false});

  final bool appleLoginEnabled;

  bool get canAttemptApple =>
      appleLoginEnabled && (Platform.isIOS || Platform.isMacOS);

  Future<AuthSession> signInWithApple(AuthRepository repository) async {
    if (!appleLoginEnabled) {
      throw const AuthFlowException('Apple 登录暂未开放。');
    }
    if (!Platform.isIOS && !Platform.isMacOS) {
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

  String _randomToken(int byteLength) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
