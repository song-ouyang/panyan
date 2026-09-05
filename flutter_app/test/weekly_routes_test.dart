import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/gyms/application/home_city_controller.dart';
import 'package:wanpan_diary/features/gyms/gyms_screen.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

JsonMap _route({
  String id = 'route-1',
  String city = '上海',
  String name = '屋檐小跳跃',
  String gymName = '1778CLIMB 静安店',
}) => {
  'id': id,
  'gym_id': 'gym-$city',
  'name': name,
  'grade': 'V3',
  'color': '红色',
  'published': true,
  'gym_name': gymName,
  'gym_city': city,
  'gym_address': '$city攀岩路88号',
  'created_at': '2026-09-01T08:30:00.000Z',
};

JsonMap _weeklyResponse(List<JsonMap> routes) => {
  'items': routes,
  'weekStart': '2026-08-30T16:00:00.000Z',
  'weekEnd': '2026-09-06T16:00:00.000Z',
};

class _WeeklyApi extends ApiClient {
  _WeeklyApi() : super(config: _config, accessTokenProvider: () => null);

  List<JsonMap> routes = [_route()];
  bool failWeekly = false;
  bool failDirectory = false;
  int directoryRequests = 0;
  final List<String> requestedPaths = [];
  final List<Map<String, dynamic>> weeklyQueries = [];
  final Map<String?, Completer<JsonMap>> pendingWeekly = {};
  Completer<JsonMap>? pendingDirectory;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requestedPaths.add(path);
    final city = queryParameters?['city'] as String?;
    if (path == '/routes/weekly') {
      weeklyQueries.add({...?queryParameters});
      if (pendingWeekly[city] case final pending?) return pending.future;
      if (failWeekly) {
        throw const ApiException(
          message: 'weekly unavailable',
          statusCode: 503,
        );
      }
      return _weeklyResponse(
        routes
            .where((route) => city == null || route['gym_city'] == city)
            .toList(),
      );
    }
    if (path == '/gyms/directory') {
      directoryRequests += 1;
      if (pendingDirectory case final pending?) return pending.future;
      if (failDirectory) {
        throw const ApiException(
          message: 'directory unavailable',
          statusCode: 503,
        );
      }
      return {
        'items': [
          for (final place in ['上海', '成都'])
            if (city == null || city == place)
              {
                'brand_id': 'brand-$place',
                'brand_name': '$place岩馆品牌',
                'city': place,
                'cities': [place],
                'store_count': 2,
                'route_count': 0,
                'verified': true,
              },
        ],
      };
    }
    throw StateError('Unexpected home request: $path');
  }
}

class _HomeHarness {
  _HomeHarness(this.controller, this.router);

  final HomeCityController controller;
  final GoRouter router;
}

Future<_HomeHarness> _pumpHome(
  WidgetTester tester,
  _WeeklyApi api, {
  String? city,
  bool compact = false,
  bool useWeeklyRouteMocks = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'home_city_selection': city ?? '',
    'home_city_manual': true,
  });
  final preferences = await SharedPreferences.getInstance();
  final controller = HomeCityController();
  await controller.initialize();
  final session = SessionController(
    preferences: preferences,
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => GymsScreen(
          api: api,
          session: session,
          cityController: controller,
          useWeeklyRouteMocks: useWeeklyRouteMocks,
        ),
      ),
      GoRoute(
        path: '/gyms/:id',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('岩馆详情 ${state.pathParameters['id']}')),
        ),
      ),
      GoRoute(
        path: '/brands/:id',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text(
              '品牌门店 ${state.pathParameters['id']} ${state.uri.queryParameters['city']}',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/routes/:id',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('线路详情 ${state.pathParameters['id']}')),
        ),
      ),
      GoRoute(
        path: '/route-submissions/new',
        builder: (context, _) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () {
                api.routes = [_route(id: 'published', name: '刚发布的线路')];
                context.pop(true);
              },
              child: const Text('完成发布'),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    controller.dispose();
    session.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.binding.setSurfaceSize(
    compact ? const Size(320, 568) : const Size(390, 844),
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(compact ? 1.35 : 1),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _HomeHarness(controller, router);
}

Finder _card(String id) => find.byKey(Key('weekly-route-$id'));

Finder _gymCard(String id) => find.byKey(Key('weekly-gym-$id'));

Finder _horizontalScrollable() => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'weekly repository sends city and limit and parses route metadata',
    () async {
      final api = _WeeklyApi();
      final routes = await GymRepository(api)
          .getWeeklyRoutes(city: '上海', limit: 7);

      expect(api.weeklyQueries.single, {'city': '上海', 'limit': 7});
      expect(routes, hasLength(1));
      final route = routes.single;
      expect(route.id, 'route-1');
      expect(route.name, '屋檐小跳跃');
      expect(route.grade, 'V3');
      expect(route.gymName, '1778CLIMB 静安店');
      expect(route.gymCity, '上海');
      expect(route.gymAddress, '上海攀岩路88号');
      expect(route.createdAt, DateTime.utc(2026, 9, 1, 8, 30));
    },
  );

  test('national weekly query omits city and uses the default limit', () async {
    final api = _WeeklyApi();
    await GymRepository(api).getWeeklyRoutes();

    expect(api.weeklyQueries.single, {'limit': 10});
  });

  test('older route payloads still parse without weekly metadata', () {
    final json = _route()
      ..remove('gym_city')
      ..remove('created_at');
    final route = ClimbingRoute.fromJson(json);

    expect(route.gymCity, isNull);
    expect(route.createdAt, isNull);
  });

  testWidgets(
    'preview gym cards stay in Chengdu and the third card can be scrolled to',
    (tester) async {
      final api = _WeeklyApi();
      final harness = await _pumpHome(
        tester,
        api,
        compact: true,
        useWeeklyRouteMocks: true,
      );

      expect(find.text('本周新线'), findsOneWidget);
      expect(find.text('示例数据'), findsNothing);
      for (final entry in const {
        'banana': '香蕉攀岩',
        'qiushan': '丘山攀岩',
        'panda': '熊猫攀岩',
      }.entries) {
        await tester.scrollUntilVisible(
          _gymCard(entry.key),
          180,
          scrollable: _horizontalScrollable(),
        );
        await tester.pumpAndSettle();
        expect(_gymCard(entry.key).hitTestable(), findsOneWidget);
        final action = find.descendant(
          of: _gymCard(entry.key),
          matching: find.text('查看岩馆'),
        );
        expect(
          tester.getRect(action).bottom,
          lessThanOrEqualTo(tester.getRect(_gymCard(entry.key)).bottom),
        );
        expect(
          find.descendant(
            of: _gymCard(entry.key),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _gymCard(entry.key),
            matching: find.textContaining('成都'),
          ),
          findsWidgets,
        );
      }
      expect(_card('route-1'), findsNothing);
      expect(api.weeklyQueries, isEmpty);

      await harness.controller.selectManually('成都');
      await tester.pumpAndSettle();
      expect(find.text('本周新线'), findsOneWidget);
      await tester.scrollUntilVisible(
        _gymCard('banana'),
        -180,
        scrollable: _horizontalScrollable(),
      );
      await tester.pumpAndSettle();
      expect(_gymCard('banana'), findsOneWidget);
      expect(_gymCard('qiushan'), findsOneWidget);
      await harness.controller.selectManually('杭州');
      await tester.pumpAndSettle();

      expect(find.text('本周新线'), findsNothing);
      for (final id in ['banana', 'qiushan', 'panda']) {
        expect(_gymCard(id), findsNothing);
      }
      expect(api.weeklyQueries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('banana and qiushan preview cards open their real gyms', (
    tester,
  ) async {
    final api = _WeeklyApi();
    final harness = await _pumpHome(
      tester,
      api,
      city: '成都',
      useWeeklyRouteMocks: true,
    );

    for (final entry in const {
      'banana': '71330197-04ac-4d15-8db6-b35a490088d4',
      'qiushan': 'fe86c13b-9f60-4f20-90fd-acdbc5a37ccb',
    }.entries) {
      await tester.scrollUntilVisible(
        _gymCard(entry.key),
        180,
        scrollable: _horizontalScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(_gymCard(entry.key));
      await tester.pumpAndSettle();

      expect(find.text('岩馆详情 ${entry.value}'), findsOneWidget);
      expect(harness.router.canPop(), isTrue);
      expect(find.text('这是示例线路，真实线路信息稍后补充。'), findsNothing);
      harness.router.pop();
      await tester.pumpAndSettle();
    }
    expect(api.weeklyQueries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panda preview opens its real brand stores in Chengdu', (
    tester,
  ) async {
    final api = _WeeklyApi();
    await _pumpHome(tester, api, city: '成都', useWeeklyRouteMocks: true);
    await tester.scrollUntilVisible(
      _gymCard('panda'),
      180,
      scrollable: _horizontalScrollable(),
    );
    await tester.pumpAndSettle();
    final requestsBefore = api.requestedPaths.length;
    await tester.tap(_gymCard('panda'));
    await tester.pumpAndSettle();

    expect(
      find.text('品牌门店 b0104aad-3abe-4830-9f53-3d85c881b6be 成都'),
      findsOneWidget,
    );
    expect(find.textContaining('资料待补充'), findsNothing);
    expect(find.text('这是示例线路，真实线路信息稍后补充。'), findsNothing);
    expect(find.textContaining('线路详情 preview-weekly'), findsNothing);
    expect(api.requestedPaths.length, requestsBefore);
    expect(api.weeklyQueries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home shows API routes with gym and city instead of brand totals',
    (tester) async {
      final api = _WeeklyApi();
      await _pumpHome(tester, api, city: '上海');

      expect(api.weeklyQueries.single['city'], '上海');
      expect(_card('route-1'), findsOneWidget);
      expect(
        find.descendant(of: _card('route-1'), matching: find.text('屋檐小跳跃')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card('route-1'),
          matching: find.textContaining('1778CLIMB 静安店'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card('route-1'),
          matching: find.textContaining('上海'),
        ),
        findsWidgets,
      );
      expect(find.text('0 条线路'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all returned weekly routes are reachable by horizontal scrolling',
    (tester) async {
      final api = _WeeklyApi()
        ..routes = [
          for (var index = 0; index < 10; index++)
            _route(id: 'r$index', name: '本周线路 $index'),
        ];
      await _pumpHome(tester, api);

      expect(_card('r0'), findsOneWidget);
      await tester.scrollUntilVisible(
        _card('r9'),
        220,
        scrollable: _horizontalScrollable(),
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();

      expect(_card('r9').hitTestable(), findsOneWidget);
      expect(find.text('本周线路 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty weekly routes hide the section and keep the directory', (
    tester,
  ) async {
    final api = _WeeklyApi()..routes = [];
    await _pumpHome(tester, api);

    expect(find.text('本周新线'), findsNothing);
    expect(find.text('本周还没有新线路'), findsNothing);
    expect(find.text('上海岩馆品牌'), findsOneWidget);
    expect(find.text('0 条线路'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'weekly failure hides the section and recovers on pull to refresh',
    (tester) async {
      final api = _WeeklyApi()..failWeekly = true;
      await _pumpHome(tester, api);

      expect(find.text('本周新线'), findsNothing);
      expect(find.text('新线路暂时没有加载出来'), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(find.text('上海岩馆品牌'), findsOneWidget);
      final directoryRequests = api.directoryRequests;
      final weeklyRequests = api.weeklyQueries.length;
      api.failWeekly = false;
      await tester.drag(
        find.byKey(const PageStorageKey('gym-home')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();

      expect(find.text('本周新线'), findsOneWidget);
      expect(_card('route-1'), findsOneWidget);
      expect(find.text('新线路暂时没有加载出来'), findsNothing);
      expect(find.text('上海岩馆品牌'), findsOneWidget);
      expect(api.weeklyQueries.length, greaterThan(weeklyRequests));
      expect(api.directoryRequests, greaterThan(directoryRequests));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directory failure does not hide loaded weekly routes', (
    tester,
  ) async {
    final api = _WeeklyApi()..failDirectory = true;
    await _pumpHome(tester, api);

    expect(_card('route-1'), findsOneWidget);
    expect(find.text('屋檐小跳跃'), findsOneWidget);
    expect(find.text('岩馆列表没有加载出来'), findsOneWidget);
    expect(find.text('新线路暂时没有加载出来'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly routes render while the directory is still pending', (
    tester,
  ) async {
    final pending = Completer<JsonMap>();
    final api = _WeeklyApi()..pendingDirectory = pending;
    await _pumpHome(tester, api);

    expect(_card('route-1'), findsOneWidget);
    expect(find.text('屋檐小跳跃'), findsOneWidget);
    pending.complete({'items': <Object>[]});
    await tester.pumpAndSettle();
    expect(_card('route-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'city change clears old routes and ignores an older late response',
    (tester) async {
      final api = _WeeklyApi();
      final harness = await _pumpHome(tester, api, city: '上海');
      expect(_card('route-1'), findsOneWidget);
      final delayed = Completer<JsonMap>();
      api.pendingWeekly['成都'] = delayed;

      await harness.controller.selectManually('成都');
      await tester.pumpAndSettle();
      expect(_card('route-1'), findsNothing);
      expect(find.text('本周新线'), findsNothing);
      expect(find.byKey(const Key('weekly-routes-loading')), findsNothing);
      expect(api.weeklyQueries.last['city'], '成都');

      await harness.controller.selectManually('上海');
      await tester.pumpAndSettle();
      expect(_card('route-1'), findsOneWidget);
      delayed.complete(
        _weeklyResponse([_route(id: 'chengdu', city: '成都', name: '成都旧响应')]),
      );
      await tester.pumpAndSettle();

      expect(_card('route-1'), findsOneWidget);
      expect(_card('chengdu'), findsNothing);
      expect(find.text('成都旧响应'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('weekly route card opens that route detail', (tester) async {
    final harness = await _pumpHome(tester, _WeeklyApi());
    await tester.tap(_card('route-1'));
    await tester.pumpAndSettle();

    expect(harness.router.canPop(), isTrue);
    expect(find.text('线路详情 route-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from route publication refreshes the weekly feed', (
    tester,
  ) async {
    final api = _WeeklyApi();
    await _pumpHome(tester, api);
    final requestsBefore = api.weeklyQueries.length;
    await tester.tap(find.text('发布线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成发布'));
    await tester.pumpAndSettle();

    expect(api.weeklyQueries.length, greaterThan(requestsBefore));
    expect(_card('published'), findsOneWidget);
    expect(find.text('刚发布的线路'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long route gym and city text fit a compact phone at large text',
    (tester) async {
      final api = _WeeklyApi()
        ..routes = [
          _route(
            name: '沿着奶油色岩壁一直向上攀爬的超级长名字线路',
            gymName: '阿坝藏族羌族自治州黑猫攀岩训练中心旗舰门店',
            city: '阿坝藏族羌族自治州',
          ),
        ];
      await _pumpHome(tester, api, compact: true);
      await tester.ensureVisible(_card('route-1'));
      await tester.pumpAndSettle();

      expect(_card('route-1').hitTestable(), findsOneWidget);
      expect(tester.getRect(_card('route-1')).left, greaterThanOrEqualTo(0));
      expect(tester.getSize(_card('route-1')).width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );
}
