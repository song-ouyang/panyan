import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_router.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/auth_repository.dart';
import 'package:wanpan_diary/features/auth/data/native_auth_service.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/auth/presentation/login_screen.dart';
import 'package:wanpan_diary/features/profile/friend_code_screen.dart';
import 'package:wanpan_diary/features/profile/friend_scanner_screen.dart';
import 'package:wanpan_diary/features/profile/friends_screen.dart';
import 'package:wanpan_diary/features/profile/public_profile_screen.dart';

const _scannedUserId = 'c680ed27-1709-4f39-8576-33fa9d6934b1';
const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _FriendScanApi extends ApiClient {
  _FriendScanApi({this.friendship = 'none'})
    : super(config: _config, accessTokenProvider: () => 'test-token');

  final List<String> calls = [];
  String friendship;
  bool failProfile = false;
  bool failRequest = false;

  Map<String, dynamic> get _user => {
    'id': _scannedUserId,
    'nickname': '扫码认识的岩友',
    'friendship': friendship,
  };

  int get friendListReads =>
      calls.where((call) => call == 'GET /users/me/friends').length;
  List<String> get writes =>
      calls.where((call) => call.startsWith('POST ')).toList();

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $path');
    return switch (path) {
      '/users/me/friends' => {
        'items': friendship == 'accepted' ? [_user] : <Object>[],
      },
      '/users/me/friend-requests' => {
        'items': friendship == 'received' ? [_user] : <Object>[],
      },
      '/users/$_scannedUserId/public' =>
        failProfile
            ? throw StateError('Profile unavailable')
            : {..._user, 'stats': <String, dynamic>{}, 'monthly': <Object>[]},
      _ => throw StateError('Unexpected GET $path'),
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('POST $path');
    if (path == '/users/$_scannedUserId/friend-request') {
      if (failRequest) throw StateError('Request unavailable');
      friendship = 'sent';
      return {'status': 'pending'};
    }
    if (path == '/users/$_scannedUserId/friend-accept') {
      friendship = 'accepted';
      return {'status': 'accepted'};
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<GlobalKey<NavigatorState>> _pumpFriends(
  WidgetTester tester,
  _FriendScanApi api, {
  Future<String?> Function()? onScan,
  Future<Object?> Function()? onShowFriendCode,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: WanpanTheme.light(),
      home: FriendsScreen(
        api: api,
        onScan: onScan ?? () async => _scannedUserId,
        onShowFriendCode: onShowFriendCode,
        onOpenProfile: (userId) => navigatorKey.currentState!.push<Object?>(
          MaterialPageRoute(
            builder: (_) => PublicProfileScreen(api: api, userId: userId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigatorKey;
}

Future<void> _scan(WidgetTester tester) async {
  await tester.tap(find.text('扫一扫'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('扫码只打开对应主页，确认加为岩友后才发送一次申请', (tester) async {
    final api = _FriendScanApi();
    addTearDown(api.dispose);
    await _pumpFriends(tester, api);

    await _scan(tester);

    expect(find.text('岩友主页'), findsOneWidget);
    expect(find.text('扫码认识的岩友'), findsOneWidget);
    expect(api.calls, contains('GET /users/$_scannedUserId/public'));
    expect(api.writes, isEmpty);
    expect(find.text('加为岩友'), findsOneWidget);

    await tester.tap(find.text('加为岩友'));
    await tester.pumpAndSettle();

    expect(api.writes, ['POST /users/$_scannedUserId/friend-request']);
    expect(find.text('等待对方确认'), findsOneWidget);
    await tester.tap(find.text('等待对方确认'));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
  });

  testWidgets('取消扫码保留岩友列表且不打开主页或发送申请', (tester) async {
    final api = _FriendScanApi();
    addTearDown(api.dispose);
    await _pumpFriends(tester, api, onScan: () async => null);
    final readsBeforeScan = api.friendListReads;

    await _scan(tester);

    expect(find.text('我的岩友'), findsOneWidget);
    expect(find.byType(PublicProfileScreen), findsNothing);
    expect(api.calls.any((call) => call.endsWith('/public')), isFalse);
    expect(api.friendListReads, readsBeforeScan);
    expect(api.writes, isEmpty);
  });

  testWidgets('扫码页尚未返回时不能重复打开', (tester) async {
    final api = _FriendScanApi();
    addTearDown(api.dispose);
    final scanResult = Completer<String?>();
    var scannerOpens = 0;
    await _pumpFriends(
      tester,
      api,
      onScan: () {
        scannerOpens += 1;
        return scanResult.future;
      },
    );

    await _scan(tester);
    await _scan(tester);
    expect(scannerOpens, 1);

    scanResult.complete(_scannedUserId);
    await tester.pumpAndSettle();
    expect(find.text('岩友主页'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  testWidgets('扫码接受已有申请后返回时重新读取岩友列表', (tester) async {
    final api = _FriendScanApi(friendship: 'received');
    addTearDown(api.dispose);
    final navigator = await _pumpFriends(tester, api);
    final initialReads = api.friendListReads;

    await _scan(tester);
    expect(api.writes, isEmpty);
    expect(find.text('接受岩友申请'), findsOneWidget);
    await tester.tap(find.text('接受岩友申请'));
    await tester.pumpAndSettle();
    expect(api.writes, ['POST /users/$_scannedUserId/friend-accept']);
    expect(find.text('已是岩友'), findsOneWidget);
    expect(api.friendListReads, initialReads);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(api.friendListReads, initialReads + 1);
    expect(find.text('我的岩友'), findsOneWidget);
    expect(find.text('新的岩友'), findsNothing);
    expect(find.text('扫码认识的岩友'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('我的好友码入口等待页面返回后刷新岩友状态', (tester) async {
    final api = _FriendScanApi();
    addTearDown(api.dispose);
    final codePageResult = Completer<Object?>();
    var codePageOpens = 0;
    await _pumpFriends(
      tester,
      api,
      onShowFriendCode: () {
        codePageOpens += 1;
        return codePageResult.future;
      },
    );
    final initialReads = api.friendListReads;

    await tester.tap(find.text('我的好友码'));
    await tester.pumpAndSettle();
    expect(codePageOpens, 1);
    expect(api.friendListReads, initialReads);
    await tester.tap(find.text('我的好友码'));
    await tester.pumpAndSettle();
    expect(codePageOpens, 1);

    api.friendship = 'accepted';
    codePageResult.complete(null);
    await tester.pumpAndSettle();

    expect(api.friendListReads, initialReads + 1);
    expect(find.text('扫码认识的岩友'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  for (final state in {
    'sent': '等待对方确认',
    'accepted': '已是岩友',
    'blocked_by_me': '已拉黑',
    'blocked_me': '暂时无法添加',
    'blocked': '暂时无法添加',
  }.entries) {
    testWidgets('扫码遵守既有 ${state.key} 关系状态', (tester) async {
      final api = _FriendScanApi(friendship: state.key);
      addTearDown(api.dispose);
      await _pumpFriends(tester, api);

      await _scan(tester);

      expect(find.text(state.value), findsOneWidget);
      expect(find.text('加为岩友'), findsNothing);
      expect(api.writes, isEmpty);
      if (state.key != 'accepted') {
        await tester.tap(find.text(state.value));
        await tester.pumpAndSettle();
        expect(api.writes, isEmpty);
      }
    });
  }

  testWidgets('扫到自己时仅查看主页，不出现添加操作', (tester) async {
    final api = _FriendScanApi(friendship: 'self');
    addTearDown(api.dispose);
    await _pumpFriends(tester, api);

    await _scan(tester);

    expect(find.text('岩友主页'), findsOneWidget);
    expect(find.text('加为岩友'), findsNothing);
    expect(find.text('接受岩友申请'), findsNothing);
    expect(api.writes, isEmpty);
  });

  testWidgets('扫码后主页加载失败可重试且不会发送申请', (tester) async {
    final api = _FriendScanApi()..failProfile = true;
    addTearDown(api.dispose);
    await _pumpFriends(tester, api);

    await _scan(tester);

    expect(find.text('这位岩友的主页暂时没有加载出来'), findsOneWidget);
    expect(api.writes, isEmpty);
    api.failProfile = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(find.text('加为岩友'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  testWidgets('扫码后的好友申请失败保留添加按钮以便重试', (tester) async {
    final api = _FriendScanApi()..failRequest = true;
    addTearDown(api.dispose);
    await _pumpFriends(tester, api);
    await _scan(tester);

    await tester.tap(find.text('加为岩友'));
    await tester.pumpAndSettle();

    expect(find.text('操作没有保存，请稍后重试'), findsOneWidget);
    expect(find.text('加为岩友'), findsOneWidget);
    expect(find.text('等待对方确认'), findsNothing);
    api.failRequest = false;
    await tester.tap(find.text('加为岩友'));
    await tester.pumpAndSettle();

    expect(find.text('等待对方确认'), findsOneWidget);
    expect(api.writes, hasLength(2));
  });

  for (final destination in ['/friends/scan', '/friends/code']) {
    testWidgets('游客打开 $destination 先登录并保留目的地', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _FriendScanApi();
      final authRepository = AuthRepository(api);
      final session = SessionController(
        preferences: await SharedPreferences.getInstance(),
        config: _config,
        tokenStore: MemorySessionTokenStore(),
      );
      addTearDown(api.dispose);
      addTearDown(session.dispose);
      await session.initialize(authRepository);
      final router = createWanpanRouter(
        api: api,
        session: session,
        authRepository: authRepository,
        nativeAuth: NativeAuthService(),
      );
      addTearDown(router.dispose);
      router.go(destination);

      await tester.pumpWidget(
        MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['from'],
        destination,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(FriendCodeScreen), findsNothing);
      expect(find.byType(FriendScannerScreen), findsNothing);
      expect(api.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('登录后返回好友码页面，二维码使用当前登录用户 UUID', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _FriendScanApi();
    final authRepository = AuthRepository(api);
    final session = SessionController(
      preferences: await SharedPreferences.getInstance(),
      config: _config,
      tokenStore: MemorySessionTokenStore(),
    );
    addTearDown(api.dispose);
    addTearDown(session.dispose);
    await session.initialize(authRepository);
    final router = createWanpanRouter(
      api: api,
      session: session,
      authRepository: authRepository,
      nativeAuth: NativeAuthService(),
    );
    addTearDown(router.dispose);
    router.go('/friends/code');
    await tester.pumpWidget(
      MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    const currentUser = UserSummary(
      id: '6d019fad-5f87-437b-bacc-4b4fe793d2aa',
      nickname: '我的真实昵称',
      role: 'user',
      profileCompleted: true,
    );
    await session.acceptSession(
      const AuthSession(
        token: 'private-session-token-never-for-qr',
        user: currentUser,
        needsProfile: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/friends/code');
    expect(find.byType(FriendCodeScreen), findsOneWidget);
    expect(find.text(currentUser.nickname), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    final screen = tester.widget<FriendCodeScreen>(
      find.byType(FriendCodeScreen),
    );
    expect(
      screen.friendUrl.toString(),
      '${_config.shareBaseUrl}/?friend=${currentUser.id}#download',
    );
    expect(screen.friendUrl.queryParameters, {'friend': currentUser.id});
    expect(screen.friendUrl.toString(), isNot(contains(session.token!)));
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
