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
  _ProfileApi() : super(config: _config, accessTokenProvider: () => 'token');

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path != '/users/me') {
      throw StateError('Unexpected profile request: $path');
    }
    return {
      ..._user.toJson(),
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
  testWidgets('编辑资料收入个人卡，成长数据合并且旧入口不重复', (tester) async {
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
    expect(growth, findsOneWidget);
    for (final label in ['本月攀爬进度', '本月最高', '累计完攀', '最高难度', '去过岩馆']) {
      expect(
        find.descendant(of: growth, matching: find.text(label)),
        findsOneWidget,
        reason: '$label 应合并在同一张成长卡中',
      );
    }

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

  testWidgets('320px 紧凑屏与最大字号下主要入口可用且无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ProfileApi();
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
      expect(tester.takeException(), isNull);
    });
  });
}
