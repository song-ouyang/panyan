import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/gyms/route_picker_screen.dart';

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
