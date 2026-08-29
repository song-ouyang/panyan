import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _incompleteUser = UserSummary(
  id: 'user-new',
  nickname: '岩友',
  role: 'user',
  profileCompleted: false,
);

const _completeUser = UserSummary(
  id: 'user-new',
  nickname: '小欧',
  bio: '喜欢动态线',
  role: 'user',
  profileCompleted: true,
);

class _ProfileApiClient extends ApiClient {
  _ProfileApiClient()
    : super(config: _config, accessTokenProvider: () => 'secure-token');

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/users/me') {
      return {
        ..._completeUser.toJson(),
        'stats': {
          'total_sends': 8,
          'gym_count': 2,
          'max_grade': 4,
          'monthly_sends': 3,
          'monthly_max_grade': 3,
        },
      };
    }
    throw StateError('Unexpected GET $path');
  }
}

class _ProfileAuthRepository extends AuthRepository {
  _ProfileAuthRepository(super.api);

  @override
  Future<UserSummary> updateProfile({
    required String nickname,
    String? avatarUrl,
    String? bio,
  }) async => UserSummary(
    id: _completeUser.id,
    nickname: nickname,
    avatarUrl: avatarUrl,
    bio: bio,
    role: 'user',
    profileCompleted: true,
  );
}

void main() {
  testWidgets('游客登录后补资料、返回原页面并可退出登录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final session = SessionController(
      preferences: preferences,
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    final api = _ProfileApiClient();
    final repository = _ProfileAuthRepository(api);
    await session.initialize(repository);
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: repository,
      nativeAuth: NativeAuthService(config: _config),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    router.go('/profile');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['from'],
      '/profile',
    );

    await session.acceptSession(
      const AuthSession(
        token: 'secure-token',
        user: _incompleteUser,
        needsProfile: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/profile/setup');
    expect(find.text('完善个人资料'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('profile-nickname')),
      _completeUser.nickname,
    );
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.text('小欧'), findsOneWidget);
    expect(find.text('本月攀爬进度'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('退出登录'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('登录后，每一次上墙都有记录'), findsOneWidget);
  });

  testWidgets('游客打开馆内投稿入口时完整保留 gymId', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    final api = _ProfileApiClient();
    final repository = _ProfileAuthRepository(api);
    await session.initialize(repository);
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: repository,
      nativeAuth: NativeAuthService(config: _config),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    router.go('/route-submissions/new?gymId=gym-1');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['from'],
      '/route-submissions/new?gymId=gym-1',
    );
  });
}
