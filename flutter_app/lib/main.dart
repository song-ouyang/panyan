import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/wanpan_app.dart';
import 'app/wanpan_router.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'features/auth/application/session_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/native_auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final preferences = await SharedPreferences.getInstance();
  final session = SessionController(preferences: preferences, config: config);
  final api = ApiClient(
    config: config,
    accessTokenProvider: () => session.token,
  );
  api.onUnauthorized = session.handleUnauthorized;
  final authRepository = AuthRepository(api);
  final nativeAuth = NativeAuthService();
  final router = createWanpanRouter(
    api: api,
    session: session,
    authRepository: authRepository,
    nativeAuth: nativeAuth,
  );

  runApp(WanpanApp(api: api, session: session, router: router));
  unawaited(_initializeSession(session, authRepository));
}

Future<void> _initializeSession(
  SessionController session,
  AuthRepository repository,
) async {
  try {
    await session.initialize(repository);
  } catch (error, stackTrace) {
    // Public gym browsing still works when a local backend is not running.
    debugPrint('Session initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
