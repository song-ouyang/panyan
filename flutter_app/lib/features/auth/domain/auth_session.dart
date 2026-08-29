import '../../../core/json/json_helpers.dart';
import '../../../core/models/user_models.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    required this.needsProfile,
  });

  factory AuthSession.fromJson(JsonMap json) => AuthSession(
    token: jsonString(json['token'], field: 'token'),
    user: UserSummary.fromJson(jsonMap(json['user'])),
    needsProfile: json['needsProfile'] == true,
  );

  final String token;
  final UserSummary user;
  final bool needsProfile;
}
