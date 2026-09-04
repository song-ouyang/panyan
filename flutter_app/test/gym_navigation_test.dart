import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/features/gyms/gym_screen.dart';
import 'package:wanpan_diary/features/gyms/map_navigation.dart';

const _gym = Gym(
  id: 'gym-1',
  name: '香蕉攀岩 凯德天府店',
  city: '成都',
  province: '四川省',
  district: '待核验',
  address: '成都市武侯区天仁路388号凯德天府L5-15铺',
  latitude: 30.602869,
  longitude: 104.069028,
  verified: false,
);

final _api = ApiClient(
  config: const AppConfig(
    environment: AppEnvironment.development,
    apiBaseUrl: 'http://127.0.0.1:3000/api',
    enableDevelopmentLogin: false,
  ),
  accessTokenProvider: () => null,
);

class _GymRepository extends GymRepository {
  _GymRepository() : super(_api);

  @override
  Future<GymDetail> getGym(String gymId) async =>
      const GymDetail(gym: _gym, routeSets: []);

  @override
  Future<List<ClimbingRoute>> getRoutes(
    String gymId, {
    String? grade,
    String? routeSetId,
  }) async => const [];
}

class _MapLauncher implements MapNavigationLauncher {
  _MapLauncher({
    this.apps = const [
      MapNavigationApp.amap,
      MapNavigationApp.tencent,
      MapNavigationApp.baidu,
      MapNavigationApp.system,
    ],
    this.opens = true,
    this.openCompleter,
  });

  final List<MapNavigationApp> apps;
  final bool opens;
  final Completer<bool>? openCompleter;
  MapNavigationApp? openedApp;
  MapNavigationTarget? openedTarget;

  @override
  TargetPlatform get currentPlatform => TargetPlatform.iOS;

  @override
  Future<List<MapNavigationApp>> availableApps(
    MapNavigationTarget target,
  ) async => apps;

  @override
  Future<bool> open(MapNavigationApp app, MapNavigationTarget target) async {
    openedApp = app;
    openedTarget = target;
    return openCompleter?.future ?? opens;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required MapNavigationLauncher launcher,
  bool compact = false,
}) async {
  if (compact) await tester.binding.setSurfaceSize(const Size(320, 568));
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) {
        if (!compact) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 20, bottom: 24),
            viewPadding: const EdgeInsets.only(top: 20, bottom: 24),
            textScaler: const TextScaler.linear(1.35),
          ),
          child: child!,
        );
      },
      home: GymScreen(
        api: _api,
        gymId: _gym.id,
        gymRepository: _GymRepository(),
        mapNavigationLauncher: launcher,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hides placeholder district and opens an installed map', (
    tester,
  ) async {
    final launcher = _MapLauncher();
    await _pump(tester, launcher: launcher);

    expect(find.textContaining('待核验'), findsNothing);
    expect(find.textContaining(_gym.address), findsOneWidget);
    expect(find.byKey(const Key('gym-navigation-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gym-navigation-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('map-navigation-sheet')), findsOneWidget);
    expect(find.text('高德地图'), findsOneWidget);
    expect(find.text('腾讯地图'), findsOneWidget);
    expect(find.text('百度地图'), findsOneWidget);
    expect(find.text('Apple 地图'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map-navigation-amap')));
    await tester.pumpAndSettle();

    expect(launcher.openedApp, MapNavigationApp.amap);
    expect(launcher.openedTarget?.name, _gym.name);
    expect(launcher.openedTarget?.address, _gym.address);
    expect(launcher.openedTarget?.latitude, _gym.latitude);
    expect(find.byKey(const Key('map-navigation-sheet')), findsNothing);
  });

  testWidgets('keeps failure feedback and sheet usable on a compact phone', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = _MapLauncher(
      apps: const [MapNavigationApp.web],
      opens: false,
    );
    await _pump(tester, launcher: launcher, compact: true);

    final navigation = find.byKey(const Key('gym-navigation-button'));
    expect(navigation.hitTestable(), findsOneWidget);
    expect(tester.getSize(navigation).height, greaterThanOrEqualTo(44));

    await tester.tap(navigation);
    await tester.pumpAndSettle();
    expect(find.text('高德地图'), findsOneWidget);
    expect(find.text('腾讯地图'), findsOneWidget);
    expect(find.text('百度地图'), findsOneWidget);
    expect(find.text('Apple 地图'), findsOneWidget);
    expect(find.text('不可用'), findsNWidgets(4));

    await tester.tap(find.byKey(const Key('map-navigation-amap')));
    await tester.pumpAndSettle();
    expect(launcher.openedApp, isNull);
    expect(find.textContaining('高德地图尚未安装或暂不可用'), findsOneWidget);

    final webOption = find.byKey(const Key('map-navigation-web'));
    expect(webOption, findsOneWidget);
    await tester.ensureVisible(webOption);
    await tester.pumpAndSettle();
    expect(webOption.hitTestable(), findsOneWidget);

    await tester.tap(webOption);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('map-navigation-error')), findsOneWidget);
    expect(find.textContaining('没有打开网页地图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed map launch cannot pop the gym after sheet dismissal', (
    tester,
  ) async {
    final completion = Completer<bool>();
    final launcher = _MapLauncher(
      apps: const [MapNavigationApp.amap],
      openCompleter: completion,
    );
    await _pump(tester, launcher: launcher);

    await tester.tap(find.byKey(const Key('gym-navigation-button')));
    await tester.pumpAndSettle();
    final sheetContext = tester.element(
      find.byKey(const Key('map-navigation-sheet')),
    );
    await tester.tap(find.byKey(const Key('map-navigation-amap')));
    await tester.pump();

    Navigator.of(sheetContext).pop();
    await tester.pump(const Duration(milliseconds: 50));
    completion.complete(true);
    await tester.pumpAndSettle();

    expect(find.byType(GymScreen), findsOneWidget);
    expect(find.byKey(const Key('map-navigation-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
