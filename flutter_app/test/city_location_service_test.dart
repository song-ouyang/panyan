import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanpan_diary/core/location/city_location_service.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  int permissionRequests = 0;
  int positionRequests = 0;
  LocationSettings? lastSettings;
  String? openedSettings;
  Object positionError = TimeoutException('No location fix');

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positionRequests++;
    lastSettings = locationSettings;
    throw positionError;
  }

  @override
  Future<bool> openAppSettings() async {
    openedSettings = 'app';
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openedSettings = 'location';
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chinese city normalization', () {
    test('municipalities take precedence over their districts', () {
      expect(
        cityFromPlacemark(
          const Placemark(
            administrativeArea: '北京市',
            subAdministrativeArea: '朝阳区',
            locality: '朝阳区',
          ),
        ),
        '北京',
      );
      for (final entry in {
        '上海市': '上海',
        '天津市': '天津',
        '重庆市': '重庆',
        'Shanghai': '上海',
      }.entries) {
        expect(
          cityFromPlacemark(Placemark(administrativeArea: entry.key)),
          entry.value,
        );
      }
    });

    test('uses prefecture over county-level city and omits trailing 市', () {
      expect(
        cityFromPlacemark(
          const Placemark(
            administrativeArea: '江苏省',
            subAdministrativeArea: '苏州市',
            locality: '昆山市',
          ),
        ),
        '苏州',
      );
      expect(
        cityFromPlacemark(
          const Placemark(
            administrativeArea: '广东省',
            subAdministrativeArea: '南山区',
            locality: ' 深圳市 ',
          ),
        ),
        '深圳',
      );
      expect(
        cityFromPlacemark(const Placemark(subAdministrativeArea: '成都市')),
        '成都',
      );
      expect(
        cityFromPlacemark(const Placemark(subAdministrativeArea: '阿里地区')),
        '阿里地区',
      );
    });

    test('supports Hong Kong and Macao without a city locality', () {
      expect(
        cityFromPlacemark(
          const Placemark(isoCountryCode: 'HK', locality: '九龙'),
        ),
        '香港',
      );
      expect(cityFromPlacemark(const Placemark(isoCountryCode: 'MO')), '澳门');
      expect(
        cityFromPlacemark(const Placemark(administrativeArea: '香港特别行政区')),
        '香港',
      );
      expect(
        cityFromPlacemark(const Placemark(administrativeArea: '澳門特別行政區')),
        '澳门',
      );
    });

    test('never turns a district, province or address into a city', () {
      for (final placemark in const [
        Placemark(),
        Placemark(administrativeArea: '广东省'),
        Placemark(locality: '朝阳区'),
        Placemark(locality: '市辖区'),
        Placemark(locality: '奉节县'),
        Placemark(locality: '广西壮族自治区'),
        Placemark(subLocality: '朝阳', street: '北京路'),
        Placemark(locality: 'Shenzhen'),
        Placemark(locality: '市'),
      ]) {
        expect(cityFromPlacemark(placemark), isNull);
      }
      expect(
        cityFromPlacemark(
          const Placemark(administrativeArea: '辽宁省', locality: '朝阳市'),
        ),
        '朝阳',
      );
    });
  });

  group('location permission and failure handling', () {
    late GeolocatorPlatform previous;
    late _LocationPlatform platform;
    const service = CityLocationService();

    setUp(() {
      previous = GeolocatorPlatform.instance;
      platform = _LocationPlatform();
      GeolocatorPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      GeolocatorPlatform.instance = previous;
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'disabled services offer location settings without requesting GPS',
      () async {
        platform.enabled = false;
        await expectLater(
          service.locateCity(),
          throwsA(
            isA<CityLocationException>()
                .having(
                  (error) => error.canOpenLocationSettings,
                  'settings',
                  isTrue,
                )
                .having(
                  (error) => error.canOpenAppSettings,
                  'app settings',
                  isFalse,
                ),
          ),
        );
        expect(platform.permissionRequests, 0);
        expect(platform.positionRequests, 0);
      },
    );

    test('denied permission can be retried without requesting GPS', () async {
      platform.permission = LocationPermission.denied;
      platform.requestedPermission = LocationPermission.denied;
      await expectLater(
        service.locateCity(),
        throwsA(
          isA<CityLocationException>()
              .having((error) => error.message, 'message', contains('未开启定位权限'))
              .having((error) => error.canOpenAppSettings, 'settings', isFalse),
        ),
      );
      expect(platform.permissionRequests, 1);
      expect(platform.positionRequests, 0);
    });

    test(
      'permanent denial offers app settings without another prompt',
      () async {
        platform.permission = LocationPermission.deniedForever;
        await expectLater(
          service.locateCity(),
          throwsA(
            isA<CityLocationException>().having(
              (error) => error.canOpenAppSettings,
              'settings',
              isTrue,
            ),
          ),
        );
        expect(platform.permissionRequests, 0);
        expect(platform.positionRequests, 0);
      },
    );

    test(
      'new permission is followed by one bounded low accuracy fix',
      () async {
        platform.permission = LocationPermission.denied;
        await expectLater(
          service.locateCity(),
          throwsA(
            isA<CityLocationException>().having(
              (error) => error.message,
              'message',
              contains('定位超时'),
            ),
          ),
        );
        expect(platform.permissionRequests, 1);
        expect(platform.positionRequests, 1);
        expect(platform.lastSettings?.accuracy, LocationAccuracy.low);
        expect(platform.lastSettings?.timeLimit, const Duration(seconds: 15));
      },
    );

    test('iOS explicitly disables background location updates', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectLater(
        service.locateCity(),
        throwsA(isA<CityLocationException>()),
      );
      final settings = platform.lastSettings! as AppleSettings;
      expect(settings.allowBackgroundLocationUpdates, isFalse);
      expect(settings.showBackgroundLocationIndicator, isFalse);
      expect(settings.accuracy, LocationAccuracy.low);
    });

    test('permission revocation while locating remains actionable', () async {
      platform.positionError = const PermissionDeniedException('revoked');
      await expectLater(
        service.locateCity(),
        throwsA(
          isA<CityLocationException>().having(
            (error) => error.canOpenAppSettings,
            'settings',
            isTrue,
          ),
        ),
      );
    });

    test('opens the requested settings destination', () async {
      expect(await service.openSettings(appSettings: true), isTrue);
      expect(platform.openedSettings, 'app');
      expect(await service.openSettings(appSettings: false), isTrue);
      expect(platform.openedSettings, 'location');
    });
  });
}
