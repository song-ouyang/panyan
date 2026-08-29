import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_app.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';

const _developmentConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.currentUser, this.validationError})
    : super(
        ApiClient(config: _developmentConfig, accessTokenProvider: () => null),
      );

  final UserSummary? currentUser;
  final Object? validationError;
  int validations = 0;

  @override
  Future<UserSummary> validateSession() async {
    validations += 1;
    if (validationError != null) throw validationError!;
    return currentUser!;
  }
}

const _user = UserSummary(
  id: 'user-1',
  nickname: '小欧',
  role: 'user',
  profileCompleted: true,
);

Future<SharedPreferences> _preferences([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  test(
    'migrates a legacy SharedPreferences JWT into secure token storage',
    () async {
      final preferences = await _preferences({
        'auth.token': 'legacy-token',
        'auth.user': jsonEncode(_user.toJson()),
      });
      final tokens = MemorySessionTokenStore();
      final session = SessionController(
        preferences: preferences,
        config: _developmentConfig,
        tokenStore: tokens,
      );
      final repository = _FakeAuthRepository(currentUser: _user);

      await session.initialize(repository);

      expect(tokens.value, 'legacy-token');
      expect(preferences.containsKey('auth.token'), isFalse);
      expect(session.isAuthenticated, isTrue);
      expect(repository.validations, 1);
    },
  );

  test(
    'restores a user from the server when secure token exists without cache',
    () async {
      final preferences = await _preferences();
      final session = SessionController(
        preferences: preferences,
        config: _developmentConfig,
        tokenStore: MemorySessionTokenStore('secure-token'),
      );
      final repository = _FakeAuthRepository(currentUser: _user);

      await session.initialize(repository);

      expect(session.isAuthenticated, isTrue);
      expect(session.user?.nickname, '小欧');
      expect(repository.validations, 1);
    },
  );

  test('a 401 clears both secure JWT and cached profile', () async {
    final preferences = await _preferences({
      'auth.user': jsonEncode(_user.toJson()),
    });
    final tokens = MemorySessionTokenStore('expired-token');
    final session = SessionController(
      preferences: preferences,
      config: _developmentConfig,
      tokenStore: tokens,
    );
    final repository = _FakeAuthRepository(
      validationError: const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: '登录已失效',
      ),
    );

    await session.initialize(repository);

    expect(session.isAuthenticated, isFalse);
    expect(tokens.value, isNull);
    expect(preferences.containsKey('auth.user'), isFalse);
  });

  test('production never exposes development login', () async {
    final session = SessionController(
      preferences: await _preferences(),
      config: const AppConfig(
        environment: AppEnvironment.production,
        apiBaseUrl: 'https://example.com/api',
        enableDevelopmentLogin: true,
      ),
      tokenStore: MemorySessionTokenStore(),
    );

    expect(session.canUseDevelopmentLogin, isFalse);
    expect(
      () => session.signInWithDevelopmentAccount(_FakeAuthRepository()),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('protected profile route redirects a guest to login', (
    tester,
  ) async {
    final preferences = await _preferences();
    final tokens = MemorySessionTokenStore();
    final session = SessionController(
      preferences: preferences,
      config: _developmentConfig,
      tokenStore: tokens,
    );
    final repository = _FakeAuthRepository();
    await session.initialize(repository);
    final api = ApiClient(
      config: _developmentConfig,
      accessTokenProvider: () => session.token,
    );
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: repository,
      nativeAuth: NativeAuthService(config: _developmentConfig),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    router.go('/profile');
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('登录后，每一次上墙都有记录'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['from'],
      '/profile',
    );
  });

  test('accepted sessions are stored outside SharedPreferences', () async {
    final preferences = await _preferences();
    final tokens = MemorySessionTokenStore();
    final session = SessionController(
      preferences: preferences,
      config: _developmentConfig,
      tokenStore: tokens,
    );

    await session.acceptSession(
      const AuthSession(
        token: 'new-secure-token',
        user: _user,
        needsProfile: false,
      ),
    );

    expect(tokens.value, 'new-secure-token');
    expect(preferences.containsKey('auth.token'), isFalse);
    expect(preferences.containsKey('auth.user'), isTrue);
  });
}
