import 'dart:async';
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
import 'package:wanpan_diary/features/gyms/application/home_city_controller.dart';
import 'package:wanpan_diary/features/ranking/ranking_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _CapturedRequest {
  const _CapturedRequest(this.path, this.queryParameters);

  final String path;
  final Map<String, dynamic> queryParameters;
}

class _RegionRankingApi extends ApiClient {
  _RegionRankingApi({
    this.regionsResponse,
    this.includeMyRank = false,
    this.nickname = '天府岩友',
    this.points = 168,
    this.rank = 1,
  }) : super(config: _config, accessTokenProvider: () => null);

  final Future<JsonMap>? regionsResponse;
  final bool includeMyRank;
  final String nickname;
  final int points;
  final int rank;
  final requests = <_CapturedRequest>[];

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(
      _CapturedRequest(path, Map<String, dynamic>.of(queryParameters ?? {})),
    );
    if (path == '/rankings/regions') {
      if (regionsResponse != null) return regionsResponse!;
      return {
        'items': [
          {'province': '四川省', 'city': '成都'},
          {'province': '广东省', 'city': '深圳'},
        ],
      };
    }
    if (path == '/rankings') {
      final entry = {
        'rank': rank,
        'user_id': 'user-chengdu',
        'nickname': nickname,
        'avatar_url': null,
        'send_count': 12,
        'total_likes': 28,
        'points': points,
        'max_grade': 6,
        'last_send': '2026-09-04T08:00:00.000Z',
      };
      return {
        'items': [entry],
        'myRank': includeMyRank ? entry : null,
        'scoring': {'completion': 10, 'gradeStep': 5, 'flash': 5, 'like': 2},
      };
    }
    if (path == '/rankings/routes') {
      final city = queryParameters?['city'] as String?;
      return {
        'items': [
          {
            'route_id': city == '成都' ? 'route-chengdu' : 'route-national',
            'route_name': city == '成都' ? '天府彩虹连动挑战线' : '全国热门挑战线',
            'grade': 'V6',
            'color': '蓝色',
            'gym_id': 'gym-chengdu',
            'gym_name': '香蕉攀岩 凯德天府店',
            'province': city == '成都' ? '四川省' : '上海市',
            'city': city ?? '上海',
            'wall_zone': '仰角区域',
            'completion_count': 128,
            'total_likes': 356,
          },
        ],
      };
    }
    throw StateError('Unexpected ranking request: $path');
  }

  _CapturedRequest latest(String path) =>
      requests.lastWhere((request) => request.path == path);
}

Future<SessionController> _createSession({
  bool authenticated = false,
  String userId = 'user-chengdu',
}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  if (authenticated) {
    await session.acceptSession(
      AuthSession(
        token: 'ranking-test-token',
        user: UserSummary(id: userId, nickname: '天府岩友'),
        needsProfile: false,
      ),
    );
  }
  return session;
}

GoRouter _createRouter({
  required _RegionRankingApi api,
  required SessionController session,
  bool compactShell = false,
  HomeCityController? cityController,
  bool retainedTabs = false,
  int initialSegment = 1,
}) {
  final rankingRoute = GoRoute(
    path: '/ranking',
    builder: (_, _) {
      final ranking = RankingScreen(
        api: api,
        session: session,
        initialSegment: initialSegment,
        cityController: cityController,
      );
      if (!compactShell) return ranking;
      return Scaffold(
        body: ranking,
        bottomNavigationBar: const SizedBox(height: 76),
      );
    },
  );
  return GoRouter(
    initialLocation: '/ranking',
    routes: [
      if (retainedTabs)
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => navigationShell,
          branches: [
            StatefulShellBranch(routes: [rankingRoute]),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) => const Scaffold(body: Text('首页')),
                ),
              ],
            ),
          ],
        )
      else
        rankingRoute,
      GoRoute(
        path: '/routes/:routeId',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('线路详情 ${state.pathParameters['routeId']}')),
        ),
      ),
      GoRoute(
        path: '/users/:userId',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('岩友主页 ${state.pathParameters['userId']}')),
        ),
      ),
    ],
  );
}

Future<void> _pumpRanking(
  WidgetTester tester, {
  required GoRouter router,
  bool compact = false,
  double textScale = 1.35,
}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      theme: WanpanTheme.light(),
      routerConfig: router,
      builder: (context, child) {
        if (!compact) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 20, bottom: 20),
            viewPadding: const EdgeInsets.only(top: 20, bottom: 20),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('我的排名采用大插画比例，名次与积分来自接口且榜单仍可进入主页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _RegionRankingApi(includeMyRank: true, rank: 7, points: 2468);
    final session = await _createSession(authenticated: true);
    final cityController = HomeCityController();
    await cityController.selectManually('成都');
    final router = _createRouter(
      api: api,
      session: session,
      cityController: cityController,
      initialSegment: 0,
      compactShell: true,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    addTearDown(cityController.dispose);

    await _pumpRanking(tester, router: router, compact: true, textScale: 1);

    final summary = find.byKey(const Key('ranking-my-summary'));
    final firstRow = find.byKey(const Key('ranked-person-user-chengdu'));
    final heroSize = tester.getSize(summary);
    expect(heroSize.width / heroSize.height, closeTo(1.15, .03));
    expect(
      find.descendant(of: summary, matching: find.text('我的成都排名')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('ranking-hero-rank'))).data,
      '#7',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('ranking-hero-points'))).data,
      '2468',
    );
    expect(find.textContaining('首攀'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('ranking-segment-0'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      firstRow,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(firstRow.hitTestable(), findsOneWidget);
    expect(
      find.descendant(of: firstRow, matching: find.text('2468')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstRow, matching: find.text('12 条完攀 · 最高 V6')),
      findsOneWidget,
    );
    await tester.tap(firstRow);
    await tester.pumpAndSettle();
    expect(find.text('岩友主页 user-chengdu'), findsOneWidget);
  });

  for (final scale in [1.35, 2.0]) {
    testWidgets('320 窄屏 $scale 倍字号的我的排名和长昵称榜单可读可点', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _RegionRankingApi(
        includeMyRank: true,
        nickname: '每个周末都想去攀岩的成都岩友',
        points: 123456789,
      );
      final session = await _createSession(authenticated: true);
      final router = _createRouter(
        api: api,
        session: session,
        initialSegment: 0,
        compactShell: true,
      );
      addTearDown(router.dispose);
      addTearDown(session.dispose);

      await _pumpRanking(
        tester,
        router: router,
        compact: true,
        textScale: scale,
      );

      final filter = find.byKey(const Key('ranking-region-button'));
      final summary = find.byKey(const Key('ranking-my-summary'));
      final firstRow = find.byKey(const Key('ranked-person-user-chengdu'));
      expect(filter.hitTestable(), findsOneWidget);
      expect(tester.getSize(filter).height, greaterThanOrEqualTo(44));
      final heroSize = tester.getSize(summary);
      expect(heroSize.width, lessThanOrEqualTo(320));
      expect(heroSize.height, greaterThanOrEqualTo(heroSize.width / 1.15));
      expect(
        tester.widget<Text>(find.byKey(const Key('ranking-hero-points'))).data,
        '123456789',
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        firstRow,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(firstRow.hitTestable(), findsOneWidget);
      expect(
        find.descendant(of: firstRow, matching: find.text('123456789')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstRow, matching: find.text('12 条完攀 · 最高 V6')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: firstRow,
          matching: find.textContaining(api.nickname),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(firstRow);
      await tester.pumpAndSettle();
      expect(find.text('岩友主页 user-chengdu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final authenticated in [false, true]) {
    testWidgets('${authenticated ? '未上榜用户' : '游客'}的大插画卡保留加入提示，不生成我的名次或积分', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _RegionRankingApi();
      final session = await _createSession(
        authenticated: authenticated,
        userId: 'viewer-without-sends',
      );
      final router = _createRouter(
        api: api,
        session: session,
        initialSegment: 0,
        compactShell: true,
      );
      addTearDown(router.dispose);
      addTearDown(session.dispose);

      await _pumpRanking(tester, router: router, compact: true, textScale: 1);

      final summary = find.byKey(const Key('ranking-my-summary'));
      expect(summary, findsOneWidget);
      expect(
        find.descendant(
          of: summary,
          matching: find.text(authenticated ? '完成线路，加入全国榜' : '登录后加入全国榜'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ranking-hero-rank')), findsNothing);
      expect(find.byKey(const Key('ranking-hero-points')), findsNothing);
      expect(
        find.descendant(of: summary, matching: find.text('168')),
        findsNothing,
        reason: '榜单他人的分数不能成为我的积分',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首次进入跟随首页成都，两种榜单均使用匹配省市且兼容市后缀', (tester) async {
    final api = _RegionRankingApi();
    final session = await _createSession();
    final cityController = HomeCityController();
    await cityController.selectManually('成都市');
    final router = _createRouter(
      api: api,
      session: session,
      cityController: cityController,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    addTearDown(cityController.dispose);

    await _pumpRanking(tester, router: router);

    expect(find.text('成都热门线路'), findsOneWidget);
    expect(api.latest('/rankings/routes').queryParameters, {
      'province': '四川省',
      'city': '成都',
    });

    await tester.tap(find.byKey(const Key('ranking-segment-0')));
    await tester.pumpAndSettle();
    expect(api.latest('/rankings').queryParameters, {
      'scope': 'city',
      'province': '四川省',
      'city': '成都',
    });
    expect(
      api.requests.where((request) => request.path != '/rankings/regions'),
      everyElement(
        predicate<_CapturedRequest>(
          (request) => request.queryParameters['city'] == '成都',
        ),
      ),
      reason: '首页城市已知时不应先请求并展示全国数据',
    );
  });

  testWidgets('保留的排行榜页面随首页切换深圳及全国，返回时不保留旧城市', (tester) async {
    final api = _RegionRankingApi();
    final session = await _createSession();
    final cityController = HomeCityController();
    await cityController.selectManually('成都');
    final router = _createRouter(
      api: api,
      session: session,
      cityController: cityController,
      retainedTabs: true,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    addTearDown(cityController.dispose);

    await _pumpRanking(tester, router: router);
    final retainedState = tester.state(find.byType(RankingScreen));
    router.go('/home');
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.byType(RankingScreen), findsNothing);

    await cityController.selectManually('深圳');
    await tester.pumpAndSettle();
    expect(api.latest('/rankings/routes').queryParameters, {
      'province': '广东省',
      'city': '深圳',
    });
    router.go('/ranking');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(RankingScreen)), same(retainedState));
    expect(find.text('深圳热门线路'), findsOneWidget);

    router.go('/home');
    await tester.pumpAndSettle();
    await cityController.selectManually(null);
    await tester.pumpAndSettle();
    expect(api.latest('/rankings/routes').queryParameters, isEmpty);
    router.go('/ranking');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(RankingScreen)), same(retainedState));
    expect(find.text('全国榜'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ranking-segment-0')));
    await tester.pumpAndSettle();
    expect(api.latest('/rankings').queryParameters, {'scope': 'national'});
  });

  testWidgets('榜内手选全国保持到首页城市变化，同城通知不会覆盖或重新请求', (tester) async {
    final api = _RegionRankingApi();
    final session = await _createSession();
    final cityController = HomeCityController();
    await cityController.selectManually('成都');
    final router = _createRouter(
      api: api,
      session: session,
      cityController: cityController,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    addTearDown(cityController.dispose);

    await _pumpRanking(tester, router: router);
    await tester.tap(find.byKey(const Key('ranking-region-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranking-region-national')));
    await tester.pumpAndSettle();
    expect(api.latest('/rankings/routes').queryParameters, isEmpty);
    final requestCount = api.requests.length;

    await cityController.selectManually('成都');
    await tester.pumpAndSettle();
    expect(find.text('全国榜'), findsOneWidget);
    expect(api.requests, hasLength(requestCount));

    await cityController.selectManually('深圳');
    await tester.pumpAndSettle();
    expect(find.text('深圳榜'), findsOneWidget);
    expect(api.latest('/rankings/routes').queryParameters, {
      'province': '广东省',
      'city': '深圳',
    });
  });

  testWidgets('地区列表迟到时保留最新未知城市，两种榜单显示该城空态且不发错误请求', (tester) async {
    final regions = Completer<JsonMap>();
    final api = _RegionRankingApi(regionsResponse: regions.future);
    final session = await _createSession();
    final cityController = HomeCityController();
    await cityController.selectManually('成都');
    final router = _createRouter(
      api: api,
      session: session,
      cityController: cityController,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);
    addTearDown(cityController.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
    );
    await tester.pump();
    await cityController.selectManually('拉萨');
    await tester.pump();
    expect(api.requests.map((request) => request.path), ['/rankings/regions']);

    regions.complete({
      'items': [
        {'province': '四川省', 'city': '成都'},
        {'province': '广东省', 'city': '深圳'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('拉萨还没有热门线路'), findsOneWidget);
    expect(find.textContaining('天府彩虹连动挑战线'), findsNothing);
    await tester.tap(find.byKey(const Key('ranking-segment-0')));
    await tester.pumpAndSettle();
    expect(find.text('拉萨榜正在等第一位岩友'), findsOneWidget);
    expect(api.requests.map((request) => request.path), ['/rankings/regions']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('成都筛选同时驱动线路榜和岩友榜并可进入线路详情', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = _RegionRankingApi();
    final session = await _createSession();
    final router = _createRouter(api: api, session: session);
    addTearDown(router.dispose);
    addTearDown(session.dispose);

    await _pumpRanking(tester, router: router);

    expect(api.latest('/rankings/routes').queryParameters, isEmpty);
    expect(
      tester
          .getSemantics(find.byKey(const Key('ranking-segment-1')))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    await tester.tap(find.byKey(const Key('ranking-region-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranking-region-四川省/成都')));
    await tester.pumpAndSettle();

    expect(find.text('成都热门线路'), findsOneWidget);
    expect(find.textContaining('天府彩虹连动挑战线'), findsOneWidget);
    expect(
      api.latest('/rankings/routes').queryParameters,
      containsPair('province', '四川省'),
    );
    expect(
      api.latest('/rankings/routes').queryParameters,
      containsPair('city', '成都'),
    );

    await tester.tap(find.text('成都榜'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('ranking-segment-0')))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    final peopleRequest = api.latest('/rankings').queryParameters;
    expect(peopleRequest, containsPair('scope', 'city'));
    expect(peopleRequest, containsPair('province', '四川省'));
    expect(peopleRequest, containsPair('city', '成都'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('ranked-person-user-chengdu')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('天府岩友'), findsOneWidget);

    await tester.tap(find.text('热门线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranked-route-route-chengdu')));
    await tester.pumpAndSettle();

    expect(find.text('线路详情 route-chengdu'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('紧凑屏与键盘打开时地区筛选仍可用且不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(() async {
      tester.view.resetViewInsets();
      await tester.binding.setSurfaceSize(null);
    });
    final api = _RegionRankingApi();
    final session = await _createSession();
    final router = _createRouter(
      api: api,
      session: session,
      compactShell: true,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);

    await _pumpRanking(tester, router: router, compact: true);

    final filter = find.byKey(const Key('ranking-region-button'));
    final route = find.byKey(const Key('ranked-route-route-national'));
    expect(filter.hitTestable(), findsOneWidget);
    expect(tester.getSize(filter).height, greaterThanOrEqualTo(44));
    expect(route, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(filter);
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('ranking-region-search'));
    expect(search, findsOneWidget);
    await tester.showKeyboard(search);
    await tester.enterText(search, '成都');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ranking-region-四川省/成都')), findsOneWidget);
    expect(find.text('深圳'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2 倍大字的紧凑屏上线路卡仍不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _RegionRankingApi();
    final session = await _createSession();
    final router = _createRouter(
      api: api,
      session: session,
      compactShell: true,
    );
    addTearDown(router.dispose);
    addTearDown(session.dispose);

    await _pumpRanking(tester, router: router, compact: true, textScale: 2);

    expect(
      find.byKey(const Key('ranked-route-route-national')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
