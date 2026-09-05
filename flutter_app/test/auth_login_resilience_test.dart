import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

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
  }) => _signIn();

  @override
  Future<AuthSession> signInWithWechatCode(String code) => _signIn();

  @override
  Future<AuthSession> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? givenName,
    String? familyName,
  }) => _signIn();

  Future<AuthSession> _signIn() async {
    loginAttempts++;
    if (loginFailures.isNotEmpty) throw loginFailures.removeFirst();
    return const AuthSession(
      token: 'new-session-token',
      user: _user,
      needsProfile: false,
    );
  }
}

class _AvailableNativeAuth extends NativeAuthService {
  @override
  bool get canAttemptApple => true;

  @override
  Future<AuthSession> signInWithApple(AuthRepository repository) =>
      repository.signInWithApple(
        identityToken: 'fixture-apple-token',
        rawNonce: 'fixture-nonce',
      );
}

Future<({SessionController session, MemorySessionTokenStore tokenStore})>
_pumpLogin(
  WidgetTester tester,
  _ResilientAuthRepository repository, {
  bool withExistingSession = false,
  AppConfig config = _config,
  NativeAuthService? nativeAuth,
  DateTime Function() now = DateTime.now,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tokenStore = MemorySessionTokenStore();
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: config,
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

  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          session: session,
          repository: repository,
          nativeAuth: nativeAuth ?? NativeAuthService(),
          returnTo: '/gyms',
          now: now,
        ),
      ),
      GoRoute(
        path: '/gyms',
        builder: (context, state) => const Scaffold(body: Text('岩馆列表')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
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

  for (final provider in ['sms-login', 'apple-login', 'development-login']) {
    for (final statusCode in [502, 503, 504]) {
      testWidgets('$provider $statusCode 不显示横幅并可通过主按钮重新登录', (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 1300));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _ResilientAuthRepository(
          _AuthApiClient(),
          loginFailures: [
            ApiException(
              statusCode: statusCode,
              code: 'SERVICE_UNAVAILABLE',
              message: 'upstream authentication unavailable',
            ),
          ],
        );
        final harness = await _pumpLogin(
          tester,
          repository,
          config: AppConfig(
            environment: AppEnvironment.development,
            apiBaseUrl: _config.apiBaseUrl,
            enableDevelopmentLogin: provider == 'development-login',
          ),
          nativeAuth: provider == 'apple-login' ? _AvailableNativeAuth() : null,
        );
        await _agreeAndEnterPhone(tester);
        await tester.enterText(find.byKey(const Key('sms-code')), '123456');
        final loginButton = find.byKey(Key(provider));

        await tester.ensureVisible(loginButton);
        await tester.tap(loginButton);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('login-error')), findsNothing);
        expect(find.byKey(const Key('login-retry')), findsNothing);
        expect(find.textContaining('登录服务暂时不可用'), findsNothing);
        expect(find.textContaining('upstream'), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(repository.loginAttempts, 1);
        expect(harness.session.isAuthenticated, isFalse);
        expect(harness.session.user, isNull);
        expect(harness.tokenStore.value, isNull);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('sms-phone')))
              .controller!
              .text,
          '13800138000',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('sms-code')))
              .controller!
              .text,
          '123456',
        );
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
        if (provider != 'apple-login') {
          final button = tester.widget<WanpanButton>(loginButton);
          expect(button.loading, isFalse);
          expect(button.onPressed, isNotNull);
        }

        await tester.tap(loginButton);
        await tester.pumpAndSettle();

        expect(repository.loginAttempts, 2);
        expect(harness.session.isAuthenticated, isTrue);
        expect(harness.tokenStore.value, 'new-session-token');
        expect(find.text('岩馆列表'), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
      });
    }
  }

  testWidgets('429 没有等待时间时保留通用提示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      loginFailures: const [
        ApiException(statusCode: 429, message: 'Too many requests'),
      ],
    );
    final harness = await _pumpLogin(tester, repository);
    await _agreeAndEnterPhone(tester);
    await tester.enterText(find.byKey(const Key('sms-code')), '123456');

    await tester.tap(find.byKey(const Key('sms-login')));
    await tester.pumpAndSettle();

    expect(find.text('请求太频繁，请稍后再试。'), findsOneWidget);
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.byKey(const Key('login-retry')), findsOneWidget);
    expect(repository.loginAttempts, 1);
    expect(harness.session.isAuthenticated, isFalse);
  });

  testWidgets('登录限流倒计时禁止重复提交，到期只恢复按钮', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime(2026, 9, 5, 12);
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      loginFailures: [
        ApiException(
          statusCode: 429,
          message: 'Too many requests',
          retryAt: now.add(const Duration(seconds: 415)),
        ),
      ],
    );
    final harness = await _pumpLogin(tester, repository, now: () => now);
    await _agreeAndEnterPhone(tester);
    await tester.enterText(find.byKey(const Key('sms-code')), '123456');
    final login = find.byKey(const Key('sms-login'));
    final submit = tester.widget<WanpanButton>(login).onPressed!;
    await tester.tap(login);
    await tester.pumpAndSettle();

    expect(find.textContaining('6 分 55 秒'), findsOneWidget);
    expect(tester.widget<WanpanButton>(login).onPressed, isNull);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('login-retry'))).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('sms-send-code')))
          .onPressed,
      isNotNull,
    );
    submit();
    await tester.pump();
    expect(repository.loginAttempts, 1);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('6 分 54 秒'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 7));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.widget<WanpanButton>(login).onPressed, isNotNull);
    expect(find.text('现在可以重新尝试登录。'), findsOneWidget);
    expect(repository.loginAttempts, 1);

    await tester.ensureVisible(find.byKey(const Key('login-retry')));
    await tester.tap(find.byKey(const Key('login-retry')));
    await tester.pumpAndSettle();
    expect(repository.loginAttempts, 2);
    expect(harness.session.isAuthenticated, isTrue);
    expect(find.text('岩馆列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('发码限流不阻止使用已有验证码登录，窄屏正常布局', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 9, 5, 12);
    final repository = _ResilientAuthRepository(
      _AuthApiClient(),
      sendFailures: [
        ApiException(
          statusCode: 429,
          message: 'Too many requests',
          retryAt: now.add(const Duration(seconds: 415)),
        ),
      ],
    );
    final harness = await _pumpLogin(tester, repository, now: () => now);
    await tester.ensureVisible(find.byKey(const Key('sms-phone')));
    await _agreeAndEnterPhone(tester);
    final send = find.byKey(const Key('sms-send-code'));
    final submit = tester.widget<TextButton>(send).onPressed!;
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(send).onPressed, isNull);
    submit();
    await tester.pump();
    expect(repository.sendAttempts, 1);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('sms-code')), '123456');
    final login = find.byKey(const Key('sms-login'));
    expect(tester.widget<WanpanButton>(login).onPressed, isNotNull);
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(repository.loginAttempts, 1);
    expect(harness.session.isAuthenticated, isTrue);
    expect(tester.takeException(), isNull);
  });
}
