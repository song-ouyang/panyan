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

  bool accountDeleted = false;

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
    if (path == '/users/me/month-dashboard') {
      final month = queryParameters?['month'] as String;
      return {
        'month': month,
        'days': const [],
        'summary': {
          'climbing_days': 0,
          'sends': 0,
          'gyms': 0,
          'max_grade': 0,
          'flashes': 0,
          'videos': 0,
        },
        'byGrade': const [],
        'byGym': const [],
      };
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> deleteJson(String path, {Object? data}) async {
    if (path == '/users/me') {
      accountDeleted = true;
      return {'deleted': true};
    }
    throw StateError('Unexpected DELETE $path');
  }
}

class _ProfileAuthRepository extends AuthRepository {
  _ProfileAuthRepository(super.api);

  final sentSmsPhones = <String>[];
  final smsLoginAttempts = <({String phone, String code})>[];

  @override
  Future<void> sendSmsCode({required String phone}) async {
    sentSmsPhones.add(phone);
  }

  @override
  Future<AuthSession> signInWithSms({
    required String phone,
    required String code,
  }) async {
    smsLoginAttempts.add((phone: phone, code: code));
    return const AuthSession(
      token: 'sms-session-token',
      user: _completeUser,
      needsProfile: false,
    );
  }

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
  testWidgets('手机号验证码发送并登录后返回原目标页面', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
      nativeAuth: NativeAuthService(),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    router.go('/login?from=/profile');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('apple-login')), findsNothing);
    expect(find.byKey(const Key('open-terms')), findsOneWidget);
    expect(find.byKey(const Key('open-privacy')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sms-phone')), '13800138000');
    await tester.tap(find.byKey(const Key('sms-send-code')));
    await tester.pump();
    expect(find.text('请先阅读并同意用户协议与隐私政策。'), findsOneWidget);
    expect(repository.sentSmsPhones, isEmpty);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sms-send-code')));
    await tester.pump();

    expect(repository.sentSmsPhones, ['13800138000']);
    expect(find.byKey(const Key('login-success')), findsOneWidget);
    expect(find.textContaining('后重发'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sms-code')), '135790');
    await tester.tap(find.byKey(const Key('sms-login')));
    await tester.pumpAndSettle();

    expect(repository.smsLoginAttempts, [
      (phone: '13800138000', code: '135790'),
    ]);
    expect(session.isAuthenticated, isTrue);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.text('小欧'), findsOneWidget);
  });

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
      nativeAuth: NativeAuthService(),
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
    expect(find.text('攀爬进度'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('profile-growth-card')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('profile-growth-card')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('profile-growth-card')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/profile/calendar');
    expect(find.text('攀岩日历'), findsOneWidget);
    expect(find.textContaining('这个月还没有记录'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('profile-settings-button')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/settings');
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/gyms');
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
      nativeAuth: NativeAuthService(),
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

  testWidgets('账号与隐私支持双重确认后注销并删除账号', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    final api = _ProfileApiClient();
    final repository = _ProfileAuthRepository(api);
    await session.initialize(repository);
    await session.acceptSession(
      const AuthSession(
        token: 'secure-token',
        user: _completeUser,
        needsProfile: false,
      ),
    );
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: repository,
      nativeAuth: NativeAuthService(),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      WanpanApp(api: api, session: session, router: router),
    );
    router.go('/profile');
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('profile-settings-button')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/settings');

    await tester.tap(
      find.byKey(const Key('account-privacy-tile')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/profile/privacy');
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('delete-account')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('delete-account')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('注销并删除账号？'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('最后确认'), findsOneWidget);

    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();

    expect(api.accountDeleted, isTrue);
    expect(session.isAuthenticated, isFalse);
    expect(router.state.uri.path, '/gyms');
  });
}
