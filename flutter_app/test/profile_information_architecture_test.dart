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
import 'package:wanpan_diary/shared/widgets/wanpan_cartoon_icon.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_cat_avatar.dart';

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
    for (final name in ['comments', 'favorites', 'likes'])
      GoRoute(
        path: '/profile/$name',
        builder: (_, _) => Scaffold(body: Text('互动管理 $name')),
      ),
    GoRoute(
      path: '/route-submissions',
      builder: (_, _) => const Scaffold(body: Text('线路发布记录页')),
    ),
    GoRoute(
      path: '/friends',
      builder: (_, _) => const Scaffold(body: Text('我的岩友页')),
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
  testWidgets('个人页四个互动入口分别进入自己的动态、评论、收藏和点赞', (tester) async {
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    await _pumpProfile(tester, router: router);

    expect(find.text('我的动态'), findsNothing, reason: '四入口取代重复的动态长行');
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-activity-favorites')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is WanpanCartoonIcon &&
              widget.kind == WanpanCartoonIconKind.favorite,
        ),
      ),
      findsOneWidget,
      reason: '收藏入口使用五角星，和点赞心形区分',
    );
    for (final name in ['posts', 'comments', 'favorites', 'likes']) {
      final shortcut = find.byKey(Key('profile-activity-$name'));
      await tester.ensureVisible(shortcut);
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/profile/$name');
      router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('昵称旁编辑图标可进入资料页，攀岩记录显示真实累计统计和日历提示', (tester) async {
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
    expect(find.text('编辑资料'), findsOneWidget);
    expect(growth, findsOneWidget);
    for (final label in [
      '攀岩记录',
      '看日历',
      '完攀线路',
      '最高难度',
      '去过岩馆',
      '18',
      'V5',
      '4',
    ]) {
      expect(
        find.descendant(of: growth, matching: find.text(label)),
        findsOneWidget,
        reason: '$label 应展示在同一张攀岩记录页中',
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

  testWidgets('攀岩记录进入攀岩日历，右上角设置进入设置页', (tester) async {
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

  testWidgets('我的攀岩精简功能文案，线路、岩友与邀请入口均可导航', (tester) async {
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    await _pumpProfile(tester, router: router);

    expect(find.byKey(const Key('profile-climbing-actions')), findsOneWidget);
    for (final obsoleteCopy in [
      '查看已发布线路与历史记录',
      '看看谁最近也在上墙',
      '扫码或分享链接，一起记录完攀',
    ]) {
      expect(find.text(obsoleteCopy), findsNothing);
    }
    for (final entry in {
      '线路发布记录': '/route-submissions',
      '我的岩友': '/friends',
      '邀请好友': '/profile/invite',
    }.entries) {
      await tester.scrollUntilVisible(
        find.text(entry.key),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, entry.value);
      router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('390px 个人页保持紧凑，首屏可见资料、四入口、统计和三个功能', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ProfileApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    await _pumpProfile(tester, router: router);

    final header = find.byKey(const Key('profile-header-card'));
    final growth = find.byKey(const Key('profile-growth-card'));
    final actions = find.byKey(const Key('profile-climbing-actions'));
    expect(tester.getSize(header).height, lessThanOrEqualTo(110));
    expect(tester.getSize(growth).height, lessThanOrEqualTo(150));
    // Reserve room for the actual app's bottom navigation and safe area.
    expect(tester.getRect(actions).bottom, lessThanOrEqualTo(734));
    expect(find.text('邀请好友').hitTestable(), findsOneWidget);
    expect(find.text('看日历').hitTestable(), findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.byType(WanpanCatAvatar)),
      findsOneWidget,
    );
    for (final name in ['posts', 'comments', 'favorites', 'likes']) {
      final shortcut = find.byKey(Key('profile-activity-$name'));
      expect(shortcut.hitTestable(), findsOneWidget);
      expect(tester.getSize(shortcut).shortestSide, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
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
      // Visiting the lower growth card can dispose the shortcut row above it.
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-activity-shortcuts')),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final shortcuts = [
        'posts',
        'comments',
        'favorites',
        'likes',
      ].map((name) => find.byKey(Key('profile-activity-$name'))).toList();
      final rowY = tester.getCenter(shortcuts.first).dy;
      for (final shortcut in shortcuts) {
        expect(shortcut.hitTestable(), findsOneWidget);
        expect(tester.getSize(shortcut).shortestSide, greaterThanOrEqualTo(44));
        expect(tester.getCenter(shortcut).dy, closeTo(rowY, 1));
      }
      for (final name in ['posts', 'comments', 'favorites', 'likes']) {
        final shortcut = find.byKey(Key('profile-activity-$name'));
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/profile/$name');
        router.pop();
        await tester.pumpAndSettle();
      }
      final growth = find.byKey(const Key('profile-growth-card'));
      await tester.scrollUntilVisible(
        growth,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('看日历').hitTestable(), findsOneWidget);
      await tester.tap(growth);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/profile/calendar');
      router.pop();
      await tester.pumpAndSettle();
      for (final entry in {
        '线路发布记录': '/route-submissions',
        '我的岩友': '/friends',
        '邀请好友': '/profile/invite',
      }.entries) {
        await tester.scrollUntilVisible(
          find.text(entry.key),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.key).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, entry.value);
        router.pop();
        await tester.pumpAndSettle();
      }
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
