import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_app.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/auth/presentation/login_screen.dart';
import 'package:wanpan_diary/features/gyms/application/home_city_controller.dart';
import 'package:wanpan_diary/features/gyms/gyms_screen.dart';
import 'package:wanpan_diary/features/notifications/application/notifications_controller.dart';
import 'package:wanpan_diary/features/notifications/notifications_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _user = UserSummary(
  id: 'notification-user',
  nickname: '消息岩友',
  profileCompleted: true,
);

const _authSession = AuthSession(
  token: 'notification-test-token',
  user: _user,
  needsProfile: false,
);

class _NotificationApi extends ApiClient {
  _NotificationApi() : super(config: _config, accessTokenProvider: () => null);

  int unread = 0;
  int inboxRequests = 0;
  final readWrites = <String>[];
  Completer<JsonMap>? readGate;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    switch (path) {
      case '/notifications':
        inboxRequests++;
        return {
          'unread': unread,
          'items': [
            {
              'id': 'notice-1',
              'type': 'system',
              'title': '欢迎记录新的完攀',
              'content': '每一次上墙，都算成长。',
              'created_at': '2026-09-05T08:00:00Z',
              'read_at': unread == 0 ? '2026-09-05T09:00:00Z' : null,
            },
          ],
        };
      case '/users/me/friend-requests':
      case '/gyms/directory':
      case '/routes/weekly':
        return {'items': <JsonMap>[]};
      case '/users/me':
        return {
          ..._user.toJson(),
          'stats': {'total_sends': 0, 'gym_count': 0, 'max_grade': 0},
        };
      default:
        throw StateError('Unexpected notification navigation GET: $path');
    }
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/notifications/notice-1/read') {
      throw StateError('Unexpected notification navigation POST: $path');
    }
    readWrites.add(path);
    await readGate?.future;
    unread = 0;
    return {'read': true};
  }
}

class _NotificationAuthRepository extends AuthRepository {
  _NotificationAuthRepository(super.api);

  final loginAttempts = <({String phone, String code})>[];

  @override
  Future<AuthSession> signInWithSms({
    required String phone,
    required String code,
  }) async {
    loginAttempts.add((phone: phone, code: code));
    return _authSession;
  }
}

Future<
  ({
    GoRouter router,
    SessionController session,
    NotificationsController notifications,
    _NotificationApi api,
    _NotificationAuthRepository auth,
    Future<void> Function() dispose,
  })
>
_pumpApp(
  WidgetTester tester, {
  bool signedIn = false,
  String initialPath = '/gyms',
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  SharedPreferences.setMockInitialValues({
    'home_city_selection': '',
    'home_city_manual': true,
  });
  final api = _NotificationApi();
  final auth = _NotificationAuthRepository(api);
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.initialize(auth);
  if (signedIn) await session.acceptSession(_authSession);
  final city = HomeCityController();
  await city.selectManually(null);
  final notifications = NotificationsController(api: api, session: session);
  notifications.start();
  final router = createWanpanRouter(
    api: api,
    session: session,
    authRepository: auth,
    nativeAuth: NativeAuthService(),
    cityController: city,
    notificationsController: notifications,
  );
  var disposed = false;
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    notifications.dispose();
    city.dispose();
    session.dispose();
    api.dispose();
    await tester.binding.setSurfaceSize(null);
  }

  addTearDown(dispose);
  router.go(initialPath);
  await tester.pumpWidget(
    WanpanApp(api: api, session: session, router: router),
  );
  await tester.pumpAndSettle();
  return (
    router: router,
    session: session,
    notifications: notifications,
    api: api,
    auth: auth,
    dispose: dispose,
  );
}

void main() {
  testWidgets('游客打开消息先登录，短信登录成功后返回真实消息页', (tester) async {
    final app = await _pumpApp(tester, initialPath: '/notifications');

    expect(app.router.state.uri.path, '/login');
    expect(app.router.state.uri.queryParameters['from'], '/notifications');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(NotificationsScreen), findsNothing);
    expect(app.api.inboxRequests, 0, reason: '游客不能请求登录用户的消息');

    await tester.enterText(find.byKey(const Key('sms-phone')), '13800138000');
    await tester.enterText(find.byKey(const Key('sms-code')), '123456');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byKey(const Key('sms-login')));
    await tester.pumpAndSettle();

    expect(app.auth.loginAttempts, [(phone: '13800138000', code: '123456')]);
    expect(app.session.isAuthenticated, isTrue);
    expect(app.router.state.uri.path, '/notifications');
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byKey(const Key('notification-notice-1')), findsOneWidget);
    expect(app.api.inboxRequests, greaterThan(0));
    expect(tester.takeException(), isNull);
    await app.dispose();
  });

  testWidgets('首页铃铛进入消息，红点随未读数变化并在已读成功或注销后消失', (tester) async {
    final app = await _pumpApp(tester, signedIn: true);
    final bell = find.byKey(const Key('home-notifications-button'));
    final unreadDot = find.byKey(const Key('home-notifications-unread'));

    expect(find.byType(GymsScreen), findsOneWidget);
    expect(bell.hitTestable(), findsOneWidget);
    expect(app.notifications.items, isNotEmpty);
    expect(unreadDot, findsNothing, reason: '有历史消息但没有未读时不显示红点');

    app.api.unread = 1;
    await app.notifications.refresh();
    await tester.pumpAndSettle();
    expect(unreadDot, findsOneWidget);
    expect(find.byTooltip('消息，1条未读'), findsOneWidget);
    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/notifications');
    expect(find.byType(NotificationsScreen), findsOneWidget);

    app.api.readGate = Completer<JsonMap>();
    await tester.tap(find.byKey(const Key('notification-notice-1')));
    await tester.pump();
    expect(app.api.readWrites, ['/notifications/notice-1/read']);
    expect(app.notifications.unreadCount, 1, reason: '已读写入成功前保留未读状态');
    app.api.readGate!.complete({'read': true});
    await tester.pumpAndSettle();
    expect(app.notifications.unreadCount, 0);

    app.router.pop();
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/gyms');
    expect(unreadDot, findsNothing);
    expect(find.byTooltip('消息'), findsOneWidget);

    app.api.unread = 1;
    await app.notifications.refresh();
    await tester.pumpAndSettle();
    expect(unreadDot, findsOneWidget);
    final inboxRequests = app.api.inboxRequests;
    await app.session.signOut();
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/gyms');
    expect(app.notifications.unreadCount, 0);
    expect(app.notifications.items, isEmpty);
    expect(unreadDot, findsNothing);
    expect(app.api.inboxRequests, inboxRequests);

    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/login');
    expect(app.router.state.uri.queryParameters['from'], '/notifications');
    expect(app.api.inboxRequests, inboxRequests);
    expect(tester.takeException(), isNull);
    await app.dispose();
  });
}
