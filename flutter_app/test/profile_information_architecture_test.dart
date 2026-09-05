import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/user_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/auth/domain/auth_session.dart';
import 'package:wanpan_diary/features/profile/profile_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

const _user = UserSummary(
  id: 'profile-user',
  nickname: '攀爬小熊',
  bio: '今天也要好好上墙',
  role: 'user',
  profileCompleted: true,
);

class _ProfileApi extends ApiClient {
  _ProfileApi({this.user = _user})
    : super(config: _config, accessTokenProvider: () => 'token');

  final UserSummary user;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/users/me') {
      throw StateError('Unexpected profile request: $path');
    }
    return {
      ...user.toJson(),
      'stats': {
        'total_sends': 18,
        'gym_count': 4,
        'max_grade': 5,
        'monthly_sends': 7,
        'monthly_max_grade': 4,
      },
    };
  }
}

Future<SessionController> _createSession() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  await session.acceptSession(
    const AuthSession(token: 'token', user: _user, needsProfile: false),
  );
  return session;
}

GoRouter _createRouter({
  required ApiClient api,
  required SessionController session,
}) => GoRouter(
  initialLocation: '/profile',
  routes: [
    GoRoute(
      path: '/profile',
      builder: (_, _) => ProfileScreen(api: api, session: session),
    ),
    GoRoute(
      path: '/profile/setup',
      builder: (_, _) => const Scaffold(body: Text('资料编辑页')),
    ),
    GoRoute(
      path: '/profile/calendar',
      builder: (_, _) => const Scaffold(body: Text('攀岩日历页')),
    ),
    GoRoute(
      path: '/profile/invite',
      builder: (_, _) => const Scaffold(body: Text('邀请好友页')),
    ),
    GoRoute(
      path: '/profile/posts',
      builder: (_, _) => const Scaffold(body: Text('动态管理页')),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const Scaffold(body: Text('设置页')),
    ),
  ],
);

Future<void> _pumpProfile(
  WidgetTester tester, {
  required GoRouter router,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 20, bottom: 16),
          viewPadding: const EdgeInsets.only(top: 20, bottom: 16),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    await body();
  } finally {
    handle.dispose();
  }
}

void main() {
  testWidgets('我的攀岩包含自己的动态管理入口', (tester) async {
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    await _pumpProfile(tester, router: router);

    await tester.ensureVisible(find.text('我的动态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的动态'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/profile/posts');
    expect(find.text('动态管理页'), findsOneWidget);
  });

  testWidgets('昵称旁编辑图标可进入资料页，攀爬进度只显示累计统计', (tester) async {
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);

    await _pumpProfile(tester, router: router);

    final header = find.byKey(const Key('profile-header-card'));
    final edit = find.byKey(const Key('profile-edit-button'));
    final growth = find.byKey(const Key('profile-growth-card'));

    expect(header, findsOneWidget);
    expect(edit, findsOneWidget);
    expect(
      find.ancestor(of: edit, matching: header),
      findsOneWidget,
      reason: '编辑资料应是顶部个人卡的内部操作',
    );
    final nickname = find.text(_user.nickname);
    expect(
      tester.getRect(edit).left,
      greaterThanOrEqualTo(tester.getRect(nickname).right),
    );
    expect(
      tester.getCenter(edit).dy,
      closeTo(tester.getCenter(nickname).dy, 1),
    );
    expect(find.byTooltip('编辑个人资料'), findsOneWidget);
    expect(find.text('编辑资料'), findsNothing);
    expect(growth, findsOneWidget);
    for (final label in ['攀爬进度', '完攀线路', '最高难度', '去过岩馆', '18', 'V5', '4']) {
      expect(
        find.descendant(of: growth, matching: find.text(label)),
        findsOneWidget,
        reason: '$label 应展示在同一张成长卡中',
      );
    }
    expect(find.text('7'), findsNothing);
    expect(find.text('V4'), findsNothing);
    expect(find.text('本月'), findsNothing);
    expect(find.text('累计'), findsNothing);
    expect(find.text('攀岩日历'), findsNothing);

    expect(find.text('成长入口'), findsNothing);
    expect(find.text('难度成长'), findsNothing);
    expect(find.byKey(const Key('profile-calendar-tile')), findsNothing);

    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/profile/setup');
    expect(router.state.uri.queryParameters['editing'], 'true');
    expect(router.state.uri.queryParameters['from'], '/profile');
  });

  testWidgets('成长卡进入攀岩日历，右上角设置进入设置页', (tester) async {
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);

    await _pumpProfile(tester, router: router);

    await _withSemantics(tester, () async {
      final settings = find.byKey(const Key('profile-settings-button'));
      expect(settings, findsOneWidget);
      expect(
        find.ancestor(of: settings, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(
        tester.getCenter(settings).dx,
        greaterThan(tester.getSize(find.byType(Scaffold)).width / 2),
      );
      expect(settings.hitTestable(), findsOneWidget);
      final settingsSemantics = find.bySemanticsLabel(RegExp('设置'));
      expect(settingsSemantics, findsOneWidget);
      expect(
        tester
            .getSemantics(settingsSemantics)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      final growth = find.byKey(const Key('profile-growth-card'));
      final growthSemantics = find.bySemanticsLabel(RegExp('查看攀岩日历'));
      expect(growthSemantics, findsOneWidget);
      expect(
        tester
            .getSemantics(growthSemantics)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/settings');

      router.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(growth);
      expect(growth.hitTestable(), findsOneWidget);
      await tester.tap(growth);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/profile/calendar');
    });
  });

  testWidgets('我的攀岩包含邀请好友入口并进入邀请页', (tester) async {
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    await _pumpProfile(tester, router: router);

    expect(find.text('我的攀岩'), findsOneWidget);
    expect(find.text('邀请好友'), findsOneWidget);
    await tester.ensureVisible(find.text('邀请好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请好友'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/profile/invite');
    expect(find.text('邀请好友页'), findsOneWidget);
  });

  testWidgets('320px 长中文昵称与最大字号下编辑图标及主要入口可用且无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longNameUser = UserSummary(
      id: 'profile-user',
      nickname: '每个周末都在认真攀爬的小熊',
      bio: '和朋友一起探索每一面岩壁',
      role: 'user',
      profileCompleted: true,
    );
    final api = _ProfileApi(user: longNameUser);
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);

    await _pumpProfile(tester, router: router, textScale: 1.35);

    await _withSemantics(tester, () async {
      final settings = find.byKey(const Key('profile-settings-button'));
      expect(settings.hitTestable(), findsOneWidget);
      expect(tester.getSize(settings).shortestSide, greaterThanOrEqualTo(44));

      final edit = find.byKey(const Key('profile-edit-button'));
      expect(edit.hitTestable(), findsOneWidget);
      expect(tester.getSize(edit).shortestSide, greaterThanOrEqualTo(44));
      final nickname = find.text(longNameUser.nickname);
      final nicknameRect = tester.getRect(nickname);
      final editRect = tester.getRect(edit);
      expect(nicknameRect.width, greaterThan(0));
      expect(editRect.left, greaterThanOrEqualTo(nicknameRect.right));
      expect(editRect.center.dy, closeTo(nicknameRect.center.dy, 1));
      expect(editRect.right, lessThanOrEqualTo(300));
      final editSemantics = find.bySemanticsLabel(RegExp('编辑个人资料'));
      expect(editSemantics, findsOneWidget);
      expect(
        tester
            .getSemantics(editSemantics)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      for (final key in ['profile-header-card', 'profile-growth-card']) {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(
        find.text('邀请好友'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('邀请好友').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The list can dispose the header after scrolling through menu entries.
      await tester.scrollUntilVisible(
        edit,
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/profile/setup');
      expect(tester.takeException(), isNull);
    });
  });
}
