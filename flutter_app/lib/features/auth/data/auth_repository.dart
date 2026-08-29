import '../../../core/network/api_client.dart';
import '../../../core/models/user_models.dart';
import '../domain/auth_session.dart';

class AuthRepository {
  const AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthSession> signInWithWechatCode(String code) async =>
      AuthSession.fromJson(
        await _apiClient.postJson('/auth/wechat', data: {'code': code}),
      );

  Future<AuthSession> signInWithMobileWechatCode(String code) async =>
      AuthSession.fromJson(
        await _apiClient.postJson('/auth/wechat-mobile', data: {'code': code}),
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
