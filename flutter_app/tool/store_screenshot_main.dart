import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wanpan_diary/app/wanpan_app.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig(
    environment: AppEnvironment.development,
    apiBaseUrl: 'http://127.0.0.1:3001/api',
    enableDevelopmentLogin: false,
    enableAppleLogin: false,
  );
  final preferences = await SharedPreferences.getInstance();
  final tokenStore = MemorySessionTokenStore();
  final session = SessionController(
    preferences: preferences,
    config: config,
    tokenStore: tokenStore,
  );
  final api = ApiClient(
    config: config,
    accessTokenProvider: () => session.token,
  );
  api.onUnauthorized = session.handleUnauthorizedResponse;
  final authRepository = AuthRepository(api);

  await session.acceptSession(
    const AuthSession(
      token: 'store-screenshot-demo-token',
      needsProfile: false,
      user: UserSummary(
        id: 'store-demo-user',
        nickname: '岩点点',
        bio: '每周两次抱石，目标 V5',
        profileCompleted: true,
      ),
    ),
  );
  await session.initialize(authRepository);

  final router = createWanpanRouter(
    api: api,
    session: session,
    authRepository: authRepository,
    nativeAuth: NativeAuthService(appleLoginEnabled: false),
  );

  runApp(WanpanApp(api: api, session: session, router: router));
}
