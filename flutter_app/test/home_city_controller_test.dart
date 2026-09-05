import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/core/location/city_location_service.dart';
import 'package:wanpan_diary/core/preferences/gym_selection_store.dart';
import 'package:wanpan_diary/features/gyms/application/home_city_controller.dart';

class _LocationService extends CityLocationService {
  _LocationService(this.resolve);

  final Future<String> Function() resolve;
  int requests = 0;
  final List<bool> settingsRequests = [];

  @override
  Future<String> locateCity() {
    requests += 1;
    return resolve();
  }

  @override
  Future<bool> openSettings({required bool appSettings}) async {
    settingsRequests.add(appSettings);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first visit locates once and persists an automatic city', () async {
    final location = _LocationService(() async => ' 上海 ');
    final controller = HomeCityController(locationService: location);
    addTearDown(controller.dispose);

    await Future.wait([controller.initialize(), controller.initialize()]);

    expect(location.requests, 1);
    expect(controller.city, '上海');
    expect(controller.isLocating, isFalse);
    expect(controller.locationError, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('home_city_selection'), '上海');
    expect(preferences.getBool('home_city_manual'), isFalse);
  });

  for (final manual in [true, false]) {
    test('城市${manual ? '手选' : '定位'}通知发出时岩馆选择器可立即读取同一城市', () async {
      SharedPreferences.setMockInitialValues({
        'home_city_selection': '上海',
        'gym_selection_v1': '{"gymId":"last-store","region":null}',
      });
      final preferences = await SharedPreferences.getInstance();
      final controller = HomeCityController(
        locationService: _LocationService(() async => '成都'),
      );
      addTearDown(controller.dispose);
      var checked = false;
      controller.addListener(() {
        if (controller.city != '成都') return;
        final pickerStore = GymSelectionStore(preferences: preferences);
        expect(pickerStore.region?.city, '成都');
        expect(pickerStore.gymId, 'last-store');
        checked = true;
      });

      if (manual) {
        await controller.selectManually('成都');
      } else {
        await controller.locate();
      }
      expect(checked, isTrue);
    });
  }

  for (final city in <String?>['成都', null]) {
    test(
      'manual ${city ?? '全国'} survives reopening without locating',
      () async {
        final location = _LocationService(() async => '上海');
        final controller = HomeCityController(locationService: location);
        await controller.selectManually(city);
        controller.dispose();

        final restored = HomeCityController(locationService: location);
        addTearDown(restored.dispose);
        await restored.initialize();

        expect(restored.city, city);
        expect(location.requests, 0);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('home_city_selection'), city ?? '');
        expect(preferences.getBool('home_city_manual'), isTrue);
      },
    );
  }

  test('a saved automatic city is refreshed on the next visit', () async {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '上海',
      'home_city_manual': false,
    });
    final location = _LocationService(() async => '成都');
    final controller = HomeCityController(locationService: location);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(location.requests, 1);
    expect(controller.city, '成都');
  });

  test('manual selection wins over a delayed location result', () async {
    final result = Completer<String>();
    final location = _LocationService(() => result.future);
    final controller = HomeCityController(locationService: location);
    addTearDown(controller.dispose);

    final locating = controller.locate();
    expect(controller.isLocating, isTrue);
    await controller.selectManually('成都');
    result.complete('上海');
    await locating;

    expect(controller.city, '成都');
    expect(controller.isLocating, isFalse);
    expect(controller.locationError, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('home_city_selection'), '成都');
    expect(preferences.getBool('home_city_manual'), isTrue);
  });

  test('manual selection wins over delayed saved preferences', () async {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '上海',
      'home_city_manual': false,
    });
    final preferences = await SharedPreferences.getInstance();
    final load = Completer<SharedPreferences>();
    final location = _LocationService(() async => '上海');
    final controller = HomeCityController(
      locationService: location,
      preferencesLoader: () => load.future,
    );
    addTearDown(controller.dispose);

    final initializing = controller.initialize();
    final selecting = controller.selectManually('成都');
    load.complete(preferences);
    await Future.wait([initializing, selecting]);

    expect(controller.city, '成都');
    expect(location.requests, 0);
    expect(preferences.getString('home_city_selection'), '成都');
    expect(preferences.getBool('home_city_manual'), isTrue);
  });

  test('permission denial keeps manual selection available', () async {
    const denied = CityLocationException(
      '请允许访问位置，或手动选择城市。',
      canOpenAppSettings: true,
    );
    final location = _LocationService(() async => throw denied);
    final controller = HomeCityController(locationService: location);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.isLocating, isFalse);
    expect(controller.locationError, same(denied));
    expect(await controller.openLocationSettings(), isTrue);
    expect(location.settingsRequests, [true]);

    await controller.selectManually('成都');
    expect(controller.city, '成都');
    expect(controller.locationError, isNull);
    expect(await controller.openLocationSettings(), isFalse);
  });

  test('disabled location services open location settings', () async {
    final location = _LocationService(
      () async => throw const CityLocationException(
        '请开启系统定位服务。',
        canOpenLocationSettings: true,
      ),
    );
    final controller = HomeCityController(locationService: location);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(await controller.openLocationSettings(), isTrue);
    expect(location.settingsRequests, [false]);
  });

  test(
    'explicit location replaces a manual selection and its preference',
    () async {
      final location = _LocationService(() async => '上海');
      final controller = HomeCityController(locationService: location);
      addTearDown(controller.dispose);

      await controller.selectManually('成都');
      await controller.locate();

      expect(controller.city, '上海');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('home_city_selection'), '上海');
      expect(preferences.getBool('home_city_manual'), isFalse);
    },
  );

  test(
    'failed explicit location preserves the previous manual selection',
    () async {
      final location = _LocationService(
        () async => throw StateError('offline'),
      );
      final controller = HomeCityController(locationService: location);
      addTearDown(controller.dispose);

      await controller.selectManually('成都');
      await controller.locate();

      expect(controller.city, '成都');
      expect(controller.isLocating, isFalse);
      expect(controller.locationError, isNotNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('home_city_selection'), '成都');
      expect(preferences.getBool('home_city_manual'), isTrue);
    },
  );

  test('empty geocoding result is a recoverable error', () async {
    final controller = HomeCityController(
      locationService: _LocationService(() async => '  '),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.city, isNull);
    expect(controller.isLocating, isFalse);
    expect(controller.locationError, isNotNull);
  });

  test('repeated locate taps share the active request', () async {
    final result = Completer<String>();
    final location = _LocationService(() => result.future);
    final controller = HomeCityController(locationService: location);
    addTearDown(controller.dispose);

    final locating = controller.locate();
    await controller.locate();
    expect(location.requests, 1);
    result.complete('上海');
    await locating;
    expect(controller.city, '上海');
  });

  test(
    'late location completion cannot notify or save after disposal',
    () async {
      final result = Completer<String>();
      final controller = HomeCityController(
        locationService: _LocationService(() => result.future),
      );
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      final locating = controller.locate();
      final beforeDispose = notifications;
      controller.dispose();

      result.complete('上海');
      await locating;

      expect(notifications, beforeDispose);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('home_city_selection'), isFalse);
    },
  );
}
