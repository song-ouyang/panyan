import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/location/city_location_service.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/features/auth/application/session_controller.dart';
import 'package:wanpan_diary/features/auth/data/session_token_store.dart';
import 'package:wanpan_diary/features/gyms/application/home_city_controller.dart';
import 'package:wanpan_diary/features/gyms/gyms_screen.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_pressable.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _LocationService extends CityLocationService {
  _LocationService(this.resolve);

  final Future<String> Function() resolve;
  int requests = 0;

  @override
  Future<String> locateCity() {
    requests += 1;
    return resolve();
  }
}

class _DirectoryApi extends ApiClient {
  _DirectoryApi() : super(config: _config, accessTokenProvider: () => null);

  final List<String?> requestedCities = [];
  final Map<String?, Completer<void>> pendingCities = {};

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/routes/weekly') return {'items': <Object>[]};
    if (path != '/gyms/directory') {
      throw StateError('Unexpected guest request: $path');
    }
    final city = queryParameters?['city'] as String?;
    requestedCities.add(city);
    await pendingCities[city]?.future;
    return {
      'items': [
        for (final place in ['上海', '成都'])
          if (city == null || city == place)
            {
              'brand_id': 'brand-$place',
              'brand_name': '$place岩馆',
              'city': place,
              'cities': [place],
              'store_count': 2,
              'route_count': 8,
              'verified': true,
            },
      ],
    };
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required HomeCityController controller,
  required _DirectoryApi api,
  bool compact = false,
  ValueNotifier<double>? keyboard,
  bool nestedNavigator = false,
}) async {
  final session = SessionController(
    preferences: await SharedPreferences.getInstance(),
    config: _config,
    tokenStore: MemorySessionTokenStore(),
  );
  addTearDown(session.dispose);
  await tester.binding.setSurfaceSize(
    compact ? const Size(320, 568) : const Size(390, 844),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) {
        Widget withInsets(double inset) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(compact ? 1.35 : 1),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: child!,
        );
        return keyboard == null
            ? withInsets(0)
            : ValueListenableBuilder<double>(
                valueListenable: keyboard,
                builder: (context, inset, _) => withInsets(inset),
              );
      },
      home: nestedNavigator
          ? Scaffold(
              extendBody: true,
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => GymsScreen(
                    api: api,
                    session: session,
                    cityController: controller,
                  ),
                ),
              ),
              bottomNavigationBar: const SizedBox(height: 90),
            )
          : GymsScreen(api: api, session: session, cityController: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCityPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-city-picker')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('use-current-location')), findsOneWidget);
}

Future<void> _chooseCity(WidgetTester tester, String? city) async {
  final option = find.byKey(Key('city-option-${city ?? 'national'}'));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _disposeHome(
  WidgetTester tester,
  HomeCityController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'root gym directory remains scrollable above a compact keyboard',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'home_city_selection': '',
        'home_city_manual': true,
      });
      final controller = HomeCityController(
        locationService: _LocationService(() async => '上海'),
      );
      final keyboard = ValueNotifier<double>(0);
      addTearDown(keyboard.dispose);
      await _pumpHome(
        tester,
        controller: controller,
        api: _DirectoryApi(),
        compact: true,
        keyboard: keyboard,
        nestedNavigator: true,
      );
      await tester.tap(find.text('找岩馆'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      final search = find.descendant(
        of: sheet,
        matching: find.byType(TextField),
      );
      final sheetContext = tester.element(search);
      expect(
        Navigator.of(sheetContext),
        same(Navigator.of(sheetContext, rootNavigator: true)),
      );

      keyboard.value = 300;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final verticalScroll = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      );
      expect(verticalScroll, findsOneWidget);
      final viewport = tester.getRect(verticalScroll);
      expect(viewport.bottom, lessThanOrEqualTo(568 - 300));
      final listScroll = tester.state<ScrollableState>(verticalScroll);
      listScroll.position.jumpTo(listScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastCard = find.ancestor(
        of: find.descendant(of: sheet, matching: find.text('成都岩馆')),
        matching: find.byType(WanpanPressable),
      );
      expect(lastCard, findsOneWidget);
      expect(tester.getRect(lastCard).top, greaterThanOrEqualTo(viewport.top));
      expect(tester.getRect(lastCard).bottom, lessThanOrEqualTo(568 - 300));

      listScroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.enterText(search, '不存在的岩馆');
      await tester.pumpAndSettle();
      expect(verticalScroll, findsOneWidget);
      final emptyPosition = tester
          .state<ScrollableState>(verticalScroll)
          .position;
      emptyPosition.jumpTo(emptyPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('还没有找到岩馆'), findsOneWidget);
      expect(
        tester.getRect(find.text('换一个城市或关键词试试。')).bottom,
        lessThanOrEqualTo(568 - 300),
      );
      expect(tester.takeException(), isNull);
      await _disposeHome(tester, controller);
    },
  );

  testWidgets('automatic location loads the matching city directory', (
    tester,
  ) async {
    final location = _LocationService(() async => '成都');
    final controller = HomeCityController(locationService: location);
    final api = _DirectoryApi();
    await _pumpHome(tester, controller: controller, api: api);

    expect(location.requests, 1);
    expect(api.requestedCities, contains('成都'));
    expect(
      find.descendant(
        of: find.byKey(const Key('home-city-picker')),
        matching: find.text('成都'),
      ),
      findsOneWidget,
    );
    expect(find.text('成都岩馆'), findsWidgets);
    expect(find.text('上海岩馆'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  for (final city in <String?>['成都', null]) {
    testWidgets('manual ${city ?? '全国'} filters and remains after reopening', (
      tester,
    ) async {
      final location = _LocationService(() async => '上海');
      final controller = HomeCityController(locationService: location);
      final api = _DirectoryApi();
      await _pumpHome(tester, controller: controller, api: api);

      await _openCityPicker(tester);
      await _chooseCity(tester, city);

      expect(controller.city, city);
      expect(api.requestedCities.last, city);
      expect(find.text('选择城市'), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('home_city_selection'), city ?? '');
      expect(preferences.getBool('home_city_manual'), isTrue);
      await _disposeHome(tester, controller);

      final restored = HomeCityController(locationService: location);
      final restoredApi = _DirectoryApi();
      await _pumpHome(tester, controller: restored, api: restoredApi);

      expect(restored.city, city);
      expect(location.requests, 1);
      expect(restoredApi.requestedCities.last, city);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-city-picker')),
          matching: find.text(city ?? '全国'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeHome(tester, restored);
    });
  }

  testWidgets('denied permission still allows manual city selection', (
    tester,
  ) async {
    final controller = HomeCityController(
      locationService: _LocationService(
        () async => throw const CityLocationException(
          '请允许访问位置，或手动选择城市。',
          canOpenAppSettings: true,
        ),
      ),
    );
    final api = _DirectoryApi();
    await _pumpHome(tester, controller: controller, api: api);

    expect(find.text('暂未获取位置，可手动选择城市'), findsOneWidget);
    await _openCityPicker(tester);
    expect(find.text('请允许访问位置，或手动选择城市。'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    await _chooseCity(tester, '成都');

    expect(api.requestedCities.last, '成都');
    expect(find.text('成都岩馆'), findsWidgets);
    expect(find.text('暂未获取位置，可手动选择城市'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  testWidgets('a slow automatic location cannot overwrite manual choice', (
    tester,
  ) async {
    final result = Completer<String>();
    final controller = HomeCityController(
      locationService: _LocationService(() => result.future),
    );
    final api = _DirectoryApi();
    await _pumpHome(tester, controller: controller, api: api);
    expect(find.text('定位中'), findsOneWidget);

    await _openCityPicker(tester);
    expect(find.text('正在定位…'), findsOneWidget);
    await _chooseCity(tester, '成都');
    result.complete('上海');
    await tester.pumpAndSettle();

    expect(controller.city, '成都');
    expect(api.requestedCities.last, '成都');
    expect(find.text('成都岩馆'), findsWidgets);
    expect(find.text('上海岩馆'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  testWidgets('use current location switches back from a manual city', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '成都',
      'home_city_manual': true,
    });
    final location = _LocationService(() async => '上海');
    final controller = HomeCityController(locationService: location);
    final api = _DirectoryApi();
    await _pumpHome(tester, controller: controller, api: api);
    expect(location.requests, 0);

    await _openCityPicker(tester);
    await tester.tap(find.byKey(const Key('use-current-location')));
    await tester.pumpAndSettle();

    expect(location.requests, 1);
    expect(api.requestedCities.last, '上海');
    expect(find.text('上海'), findsOneWidget);
    expect(find.text('选择城市'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('home_city_manual'), isFalse);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  testWidgets('an open city picker updates when the directory arrives', (
    tester,
  ) async {
    final controller = HomeCityController(
      locationService: _LocationService(
        () async => throw const CityLocationException('暂时无法定位。'),
      ),
    );
    final directory = Completer<void>();
    final api = _DirectoryApi()..pendingCities[null] = directory;
    await _pumpHome(tester, controller: controller, api: api);
    await _openCityPicker(tester);
    expect(find.byKey(const Key('city-option-成都')), findsNothing);

    directory.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('city-option-成都')), findsOneWidget);
    await _chooseCity(tester, '成都');
    expect(api.requestedCities.last, '成都');
    expect(find.text('成都岩馆'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  testWidgets(
    'location completing during sheet dismissal cannot pop the home',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'home_city_selection': '成都',
        'home_city_manual': true,
      });
      final result = Completer<String>();
      final controller = HomeCityController(
        locationService: _LocationService(() => result.future),
      );
      final api = _DirectoryApi();
      await _pumpHome(tester, controller: controller, api: api);
      await _openCityPicker(tester);
      final sheetContext = tester.element(
        find.byKey(const Key('use-current-location')),
      );
      await tester.tap(find.byKey(const Key('use-current-location')));
      await tester.pump();
      expect(find.text('正在定位…'), findsOneWidget);

      Navigator.of(sheetContext).pop();
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheetContext.mounted, isTrue);
      result.complete('上海');
      await tester.pumpAndSettle();

      expect(find.byType(GymsScreen), findsOneWidget);
      expect(find.text('选择城市'), findsNothing);
      expect(find.text('上海岩馆'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _disposeHome(tester, controller);
    },
  );

  testWidgets('a delayed old directory cannot replace a newer city selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '成都',
      'home_city_manual': true,
    });
    final controller = HomeCityController(
      locationService: _LocationService(() async => '上海'),
    );
    final api = _DirectoryApi();
    await _pumpHome(tester, controller: controller, api: api);
    final oldDirectory = Completer<void>();
    api.pendingCities['上海'] = oldDirectory;
    await controller.locate();
    await tester.pumpAndSettle();
    await _openCityPicker(tester);
    await _chooseCity(tester, '成都');

    oldDirectory.complete();
    await tester.pumpAndSettle();

    expect(controller.city, '成都');
    expect(find.text('成都岩馆'), findsWidgets);
    expect(find.text('上海岩馆'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  testWidgets('a located city without gyms keeps its honest empty state', (
    tester,
  ) async {
    final controller = HomeCityController(
      locationService: _LocationService(() async => '拉萨'),
    );
    final api = _DirectoryApi();
    await _pumpHome(tester, controller: controller, api: api);

    expect(api.requestedCities, contains('拉萨'));
    expect(find.text('拉萨'), findsOneWidget);
    expect(find.text('这个城市还没有岩馆'), findsOneWidget);
    expect(find.text('上海岩馆'), findsNothing);
    expect(find.text('成都岩馆'), findsNothing);

    await _openCityPicker(tester);
    expect(find.byKey(const Key('city-option-拉萨')), findsOneWidget);
    expect(find.byKey(const Key('city-option-上海')), findsOneWidget);
    await _chooseCity(tester, '成都');
    expect(find.text('成都岩馆'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });

  testWidgets('long city remains tappable on a compact phone with large text', (
    tester,
  ) async {
    const city = '阿坝藏族羌族自治州';
    SharedPreferences.setMockInitialValues({
      'home_city_selection': city,
      'home_city_manual': true,
    });
    final controller = HomeCityController(
      locationService: _LocationService(() async => '上海'),
    );
    await _pumpHome(
      tester,
      controller: controller,
      api: _DirectoryApi(),
      compact: true,
    );

    final picker = find.byKey(const Key('home-city-picker'));
    expect(picker.hitTestable(), findsOneWidget);
    expect(tester.getSize(picker).height, greaterThanOrEqualTo(44));
    expect(tester.getRect(picker).right, lessThanOrEqualTo(320));
    expect(find.text(city), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _openCityPicker(tester);
    await tester.scrollUntilVisible(
      find.byKey(Key('city-option-$city')),
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _disposeHome(tester, controller);
  });
}
