import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/models/user_models.dart';
import '../domain/auth_session.dart';

class AuthRepository {
  const AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<void> sendSmsCode({required String phone}) async {
    final response = await _apiClient.postJson(
      '/auth/sms/send',
      data: {'phone': phone},
    );
    if (response['sent'] != true) {
      throw const ApiException(
        code: 'SMS_SEND_INCOMPLETE',
        message: '验证码发送没有完成，请重试。',
      );
    }
  }

  Future<AuthSession> signInWithSms({
    required String phone,
    required String code,
  }) async => AuthSession.fromJson(
    await _apiClient.postJson(
      '/auth/sms/login',
      data: {'phone': phone, 'code': code},
    ),
  );

  Future<AuthSession> signInWithWechatCode(String code) async =>
      AuthSession.fromJson(
        await _apiClient.postJson('/auth/wechat', data: {'code': code}),
      );

  Future<AuthSession> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? givenName,
    String? familyName,
  }) async => AuthSession.fromJson(
    await _apiClient.postJson(
      '/auth/apple',
      data: {
        'identityToken': identityToken,
        'rawNonce': rawNonce,
        'givenName': givenName,
        'familyName': familyName,
      },
    ),
  );

  Future<UserSummary> validateSession() async =>
      UserSummary.fromJson(await _apiClient.getJson('/users/me'));

  Future<UserSummary> updateProfile({
    required String nickname,
    String? avatarUrl,
    String? bio,
  }) async => UserSummary.fromJson(
    await _apiClient.patchJson(
      '/users/me',
      data: {'nickname': nickname, 'avatarUrl': avatarUrl, 'bio': bio},
    ),
  );
}
