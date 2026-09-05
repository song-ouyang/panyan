import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/core/preferences/gym_selection_store.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/gyms/route_picker_screen.dart';
import 'package:wanpan_diary/features/gyms/gym_screen.dart';

void main() {
  const gym = Gym(
    id: 'gym-1',
    name: '香蕉攀岩·南山店',
    city: '深圳',
    province: '广东省',
    district: '南山区',
    address: '科技园',
    verified: true,
  );
  const otherGym = Gym(
    id: 'gym-2',
    name: '第二家岩馆',
    city: '深圳',
    province: '广东省',
    address: '南山大道',
    verified: true,
  );

  testWidgets('手选岩馆后重建页面仍恢复同一家门店', (tester) async {
    final harness = await _SelectionHarness.create([gym, otherGym]);
    await harness.pumpPicker(tester);
    expect(find.text('先选一家岩馆'), findsOneWidget);

    await tester.tap(find.text('选择岩馆').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(otherGym.name));
    await tester.pumpAndSettle();
    expect(harness.store.gymId, otherGym.id);

    await tester.pumpWidget(const SizedBox());
    await harness.pumpPicker(tester);
    expect(find.text(otherGym.name), findsOneWidget);
    expect(harness.repository.requestedGymIds, [otherGym.id, otherGym.id]);
  });

  testWidgets('明确门店入口优先于记忆并成为下次默认岩馆', (tester) async {
    final harness = await _SelectionHarness.create([gym, otherGym]);
    await harness.store.rememberGym(gym);
    await harness.pumpPicker(tester, initialGymId: otherGym.id);
    expect(find.text(otherGym.name), findsOneWidget);
    expect(harness.store.gymId, otherGym.id);
    expect(harness.repository.requestedGymIds, [otherGym.id]);

    await tester.pumpWidget(const SizedBox());
    await harness.pumpPicker(tester);
    expect(find.text(otherGym.name), findsOneWidget);
  });

  testWidgets('已删除的记忆岩馆清空后等待手选而不选择列表首项', (tester) async {
    final harness = await _SelectionHarness.create([otherGym]);
    await harness.store.rememberGym(gym);
    await harness.pumpPicker(tester);
    expect(find.text('先选一家岩馆'), findsOneWidget);
    expect(find.text(otherGym.name), findsNothing);
    expect(harness.store.gymId, isNull);
    expect(harness.repository.requestedGymIds, [gym.id]);
  });

  testWidgets('暂时无法加载岩馆时保留记忆以便重试', (tester) async {
    final harness = await _SelectionHarness.create([gym]);
    harness.repository.loadDetail = (_) async =>
        throw const ApiException(message: 'offline', statusCode: 503);
    await harness.store.rememberGym(gym);
    await harness.pumpPicker(tester);
    expect(find.text('线路没有加载出来'), findsOneWidget);
    expect(harness.store.gymId, gym.id);

    harness.repository.loadDetail = null;
    await tester.pumpWidget(const SizedBox());
    await harness.pumpPicker(tester);
    expect(find.text(gym.name), findsOneWidget);
  });

  testWidgets('旧岩馆详情晚返回不能覆盖手动切换的门店', (tester) async {
    final harness = await _SelectionHarness.create([gym, otherGym]);
    final delayedDetail = Completer<GymDetail>();
    harness.repository.loadDetail = (id) => id == gym.id
        ? delayedDetail.future
        : Future.value(GymDetail(gym: otherGym, routeSets: const []));
    await harness.pumpPicker(tester, initialGymId: gym.id, settle: false);
    await tester.pump();
    await tester.tap(find.text(gym.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(otherGym.name));
    await tester.pumpAndSettle();

    delayedDetail.complete(GymDetail(gym: gym, routeSets: const []));
    await tester.pumpAndSettle();
    expect(find.text(otherGym.name), findsOneWidget);
    expect(find.text(gym.name), findsNothing);
    expect(harness.store.gymId, otherGym.id);
  });

  testWidgets('浏览具体门店后找线路页面沿用该岩馆', (tester) async {
    final harness = await _SelectionHarness.create([gym, otherGym]);
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: GymScreen(
          api: harness.api,
          gymId: otherGym.id,
          gymRepository: harness.repository,
          selectionStore: harness.store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.store.gymId, otherGym.id);

    await tester.pumpWidget(const SizedBox());
    await harness.pumpPicker(tester);
    expect(find.text(otherGym.name), findsOneWidget);
  });

  testWidgets('被新页面盖住的旧门店请求不能覆盖新的岩馆记忆', (tester) async {
    final harness = await _SelectionHarness.create([gym, otherGym]);
    final delayedDetail = Completer<GymDetail>();
    harness.repository.loadDetail = (_) => delayedDetail.future;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: WanpanTheme.light(),
        home: GymScreen(
          api: harness.api,
          gymId: gym.id,
          gymRepository: harness.repository,
          selectionStore: harness.store,
        ),
      ),
    );
    await tester.pump();
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('新页面'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await harness.store.rememberGym(otherGym);
    delayedDetail.complete(GymDetail(gym: gym, routeSets: const []));
    await tester.pumpAndSettle();
    expect(harness.store.gymId, otherGym.id);
  });
  final currentSet = RouteSet(
    id: 'set-current',
    gymId: gym.id,
    name: '当前线路',
    startsOn: DateTime(2026, 8, 1),
    active: true,
  );
  final oldSet = RouteSet(
    id: 'set-old',
    gymId: gym.id,
    name: '旧线路',
    startsOn: DateTime(2026, 7, 1),
    active: false,
  );
  const routes = <ClimbingRoute>[
    ClimbingRoute(
      id: 'route-orange',
      gymId: 'gym-1',
      routeSetId: 'set-current',
      routeSetName: '当前线路',
      name: '橙色月亮线',
      grade: 'V3',
      color: '橙',
      wallZone: 'A区',
      published: true,
    ),
    ClimbingRoute(
      id: 'route-blue',
      gymId: 'gym-1',
      routeSetId: 'set-current',
      routeSetName: '当前线路',
      name: '蓝色动态线',
      grade: 'V4',
      color: '蓝',
      wallZone: 'B区',
      published: true,
    ),
    ClimbingRoute(
      id: 'route-old-orange',
      gymId: 'gym-1',
      routeSetId: 'set-old',
      routeSetName: '旧线路',
      name: '橙色旧线',
      grade: 'V3',
      color: '橙',
      wallZone: 'C区',
      published: true,
    ),
  ];

  testWidgets('关键词、难度和周期组合筛选后可直达打卡', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const config = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: 'http://127.0.0.1:3000/api',
      enableDevelopmentLogin: false,
    );
    final session = SessionController(
      preferences: preferences,
      config: config,
      tokenStore: MemorySessionTokenStore(),
    );
    final api = ApiClient(config: config, accessTokenProvider: () => null);
    final repository = _FakeGymRepository(
      api,
      gym: gym,
      routeSets: [currentSet, oldSet],
      routes: routes,
    );
    final router = GoRouter(
      initialLocation: '/pick',
      routes: [
        GoRoute(
          path: '/pick',
          builder: (_, _) => RoutePickerScreen(
            api: api,
            session: session,
            initialGymId: gym.id,
            gymRepository: repository,
          ),
        ),
        GoRoute(
          path: '/routes/:routeId/checkin',
          builder: (_, state) => Scaffold(
            body: Text('checkin:${state.pathParameters['routeId']}'),
          ),
        ),
        GoRoute(
          path: '/routes/:routeId',
          builder: (_, state) =>
              Scaffold(body: Text('detail:${state.pathParameters['routeId']}')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: WanpanTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('橙色月亮线'), findsOneWidget);
    expect(find.text('蓝色动态线'), findsOneWidget);
    expect(find.text('橙色旧线'), findsNothing);

    await tester.enterText(find.byType(TextField), '橙');
    await tester.pump();
    expect(find.text('橙色月亮线'), findsOneWidget);
    expect(find.text('蓝色动态线'), findsNothing);

    await tester.tap(find.text('全部难度'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'V4'));
    await tester.pumpAndSettle();
    expect(find.text('没找到这条线路'), findsOneWidget);

    await tester.tap(find.text('V4'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'V3'));
    await tester.pumpAndSettle();
    expect(find.text('橙色月亮线'), findsOneWidget);

    await tester.tap(find.text('当前线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '旧线路'));
    await tester.pumpAndSettle();
    expect(find.text('橙色旧线'), findsOneWidget);
    expect(find.text('橙色月亮线'), findsNothing);

    await tester.tap(find.text('橙色旧线'));
    await tester.pumpAndSettle();
    expect(find.text('checkin:route-old-orange'), findsOneWidget);
  });
}

class _SelectionHarness {
  _SelectionHarness({
    required this.api,
    required this.session,
    required this.store,
    required this.repository,
  });

  final ApiClient api;
  final SessionController session;
  final GymSelectionStore store;
  final _SelectionRepository repository;

  static Future<_SelectionHarness> create(List<Gym> gyms) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const config = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: 'http://127.0.0.1:3000/api',
      enableDevelopmentLogin: false,
    );
    final api = ApiClient(config: config, accessTokenProvider: () => null);
    return _SelectionHarness(
      api: api,
      session: SessionController(
        preferences: preferences,
        config: config,
        tokenStore: MemorySessionTokenStore(),
      ),
      store: GymSelectionStore(preferences: preferences),
      repository: _SelectionRepository(api, gyms),
    );
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    String? initialGymId,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: RoutePickerScreen(
          api: api,
          session: session,
          gymRepository: repository,
          selectionStore: store,
          initialGymId: initialGymId,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }
}

class _SelectionRepository extends GymRepository {
  _SelectionRepository(super.api, this.gyms);

  final List<Gym> gyms;
  final List<String> requestedGymIds = [];
  Future<GymDetail> Function(String)? loadDetail;

  @override
  Future<List<Gym>> getGyms({String? city, String? query}) async => gyms;

  @override
  Future<GymDetail> getGym(String gymId) async {
    requestedGymIds.add(gymId);
    if (loadDetail != null) return loadDetail!(gymId);
    final gym = gyms.where((gym) => gym.id == gymId).firstOrNull;
    if (gym == null) {
      throw const ApiException(message: 'Gym not found', statusCode: 404);
    }
    return GymDetail(gym: gym, routeSets: const []);
  }

  @override
  Future<List<ClimbingRoute>> getRoutes(
    String gymId, {
    String? grade,
    String? routeSetId,
  }) async => const [];
}

class _FakeGymRepository extends GymRepository {
  _FakeGymRepository(
    super.api, {
    required this.gym,
    required this.routeSets,
    required this.routes,
  });

  final Gym gym;
  final List<RouteSet> routeSets;
  final List<ClimbingRoute> routes;

  @override
  Future<List<Gym>> getGyms({String? city, String? query}) async => [gym];

  @override
  Future<GymDetail> getGym(String gymId) async =>
      GymDetail(gym: gym, routeSets: routeSets);

  @override
  Future<List<ClimbingRoute>> getRoutes(
    String gymId, {
    String? grade,
    String? routeSetId,
  }) async => routes;
}
