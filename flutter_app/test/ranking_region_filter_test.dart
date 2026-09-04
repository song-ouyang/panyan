import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
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
  _RegionRankingApi() : super(config: _config, accessTokenProvider: () => null);

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
      return {
        'items': [
          {'province': '四川省', 'city': '成都'},
          {'province': '广东省', 'city': '深圳'},
        ],
      };
    }
    if (path == '/rankings') {
      return {
        'items': [
          {
            'rank': 1,
            'user_id': 'user-chengdu',
            'nickname': '天府岩友',
            'avatar_url': null,
            'send_count': 12,
            'total_likes': 28,
            'points': 168,
            'max_grade': 6,
            'last_send': '2026-09-04T08:00:00.000Z',
          },
        ],
        'myRank': null,
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

Future<SessionController> _createSession() async {
  SharedPreferences.setMockInitialValues({});
  return SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
}

GoRouter _createRouter({
  required _RegionRankingApi api,
  required SessionController session,
  bool compactShell = false,
}) => GoRouter(
  initialLocation: '/ranking',
  routes: [
    GoRoute(
      path: '/ranking',
      builder: (_, _) {
        final ranking = RankingScreen(
          api: api,
          session: session,
          initialSegment: 1,
        );
        if (!compactShell) return ranking;
        return Scaffold(
          body: ranking,
          bottomNavigationBar: const SizedBox(height: 76),
        );
      },
    ),
    GoRoute(
      path: '/routes/:routeId',
      builder: (_, state) => Scaffold(
        body: Center(child: Text('线路详情 ${state.pathParameters['routeId']}')),
      ),
    ),
  ],
);

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
