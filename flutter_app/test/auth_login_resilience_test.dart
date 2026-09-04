import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/auth/presentation/login_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _user = UserSummary(
  id: 'user-1',
  nickname: '岩友',
  role: 'user',
  profileCompleted: true,
);

class _AuthApiClient extends ApiClient {
  _AuthApiClient() : super(config: _config, accessTokenProvider: () => null);
}

class _ResilientAuthRepository extends AuthRepository {
  _ResilientAuthRepository(
    super.api, {
    Iterable<Object> sendFailures = const [],
    Iterable<Object> loginFailures = const [],
  }) : sendFailures = Queue<Object>.of(sendFailures),
       loginFailures = Queue<Object>.of(loginFailures);

  final Queue<Object> sendFailures;
  final Queue<Object> loginFailures;
  int sendAttempts = 0;
  int loginAttempts = 0;

  @override
  Future<void> sendSmsCode({required String phone}) async {
    sendAttempts++;
    if (sendFailures.isNotEmpty) throw sendFailures.removeFirst();
  }

  @override
  Future<AuthSession> signInWithSms({
    required String phone,
    required String code,
  }) async {
    loginAttempts++;
    if (loginFailures.isNotEmpty) throw loginFailures.removeFirst();
    return const AuthSession(
      token: 'new-session-token',
      user: _user,
      needsProfile: false,
    );
  }
}

Future<({SessionController session, MemorySessionTokenStore tokenStore})>
_pumpLogin(
  WidgetTester tester,
  _ResilientAuthRepository repository, {
  bool withExistingSession = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tokenStore = MemorySessionTokenStore();
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: tokenStore,
  );
  await session.initialize(repository);
  if (withExistingSession) {
    await session.acceptSession(
      const AuthSession(
        token: 'stale-session-token',
        user: _user,
        needsProfile: false,
      ),
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      home: LoginScreen(
        session: session,
        repository: repository,
        nativeAuth: NativeAuthService(),
        returnTo: '/gyms',
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session: session, tokenStore: tokenStore);
}

Future<void> _agreeAndEnterPhone(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('sms-phone')), '13800138000');
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('503 短信失败显示友好提示并可原地重试', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      sendFailures: const [
        ApiException(
          statusCode: 503,
          code: 'SERVICE_UNAVAILABLE',
          message: 'upstream sms unavailable',
        ),
      ],
    );
    await _pumpLogin(tester, repository);
    await _agreeAndEnterPhone(tester);

    await tester.tap(find.byKey(const Key('sms-send-code')));
    await tester.pumpAndSettle();

    expect(find.text('短信服务暂时不可用，请稍后重试。'), findsOneWidget);
    expect(find.byKey(const Key('login-retry')), findsOneWidget);
    expect(repository.sendAttempts, 1);

    await tester.ensureVisible(find.byKey(const Key('login-retry')));
    await tester.tap(find.byKey(const Key('login-retry')));
    await tester.pump();

    expect(repository.sendAttempts, 2);
    expect(find.text('验证码已发送，请注意查收。'), findsOneWidget);
    expect(find.byKey(const Key('login-retry')), findsNothing);
  });

  testWidgets('旧后端 Zod 500 不泄露技术错误', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      sendFailures: const [
        ApiException(
          statusCode: 500,
          code: 'VALIDATION_ERROR',
          message: 'ZodError: invalid input',
          issues: [
            {
              'path': ['phone'],
            },
          ],
        ),
      ],
    );
    await _pumpLogin(tester, repository);
    await _agreeAndEnterPhone(tester);

    await tester.tap(find.byKey(const Key('sms-send-code')));
    await tester.pumpAndSettle();

    expect(find.text('手机号或验证码格式不正确，请检查后重试。'), findsOneWidget);
    expect(find.textContaining('ZodError'), findsNothing);
    expect(find.byKey(const Key('login-retry')), findsOneWidget);
  });

  testWidgets('旧后端 404 说明手机号登录端点暂不支持', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      sendFailures: const [
        ApiException(statusCode: 404, message: 'Route POST not found'),
      ],
    );
    await _pumpLogin(tester, repository);
    await _agreeAndEnterPhone(tester);

    await tester.tap(find.byKey(const Key('sms-send-code')));
    await tester.pumpAndSettle();

    expect(find.text('当前服务器版本暂不支持手机号登录，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('Route POST'), findsNothing);
  });

  testWidgets('401 登录失败会清理本地旧 session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      loginFailures: const [
        ApiException(
          statusCode: 401,
          code: 'UNAUTHORIZED',
          message: '验证码错误或已过期。',
        ),
      ],
    );
    final harness = await _pumpLogin(
      tester,
      repository,
      withExistingSession: true,
    );
    await _agreeAndEnterPhone(tester);
    await tester.enterText(find.byKey(const Key('sms-code')), '000000');

    await tester.tap(find.byKey(const Key('sms-login')));
    await tester.pumpAndSettle();

    expect(find.text('验证码错误或已失效，请重新获取。'), findsOneWidget);
    expect(repository.loginAttempts, 1);
    expect(harness.session.isAuthenticated, isFalse);
    expect(harness.session.user, isNull);
    expect(harness.tokenStore.value, isNull);
  });
}
