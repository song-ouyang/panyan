import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class CityLocationException implements Exception {
  const CityLocationException(
    this.message, {
    this.canOpenAppSettings = false,
    this.canOpenLocationSettings = false,
  });

  final String message;
  final bool canOpenAppSettings;
  final bool canOpenLocationSettings;

  @override
  String toString() => message;
}

/// Resolves one foreground location into a city. Coordinates are not retained.
class CityLocationService {
  const CityLocationService();

  static const _positionTimeout = Duration(seconds: 15);
  static const _geocodingTimeout = Duration(seconds: 10);
  static const _platformTimeout = Duration(seconds: 5);

  Future<String> locateCity() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      throw const CityLocationException('当前设备暂不支持定位，请手动选择城市。');
    }
    try {
      final enabled = await Geolocator.isLocationServiceEnabled().timeout(
        _platformTimeout,
      );
      if (!enabled) throw _serviceDisabled;

      var permission = await Geolocator.checkPermission().timeout(
        _platformTimeout,
      );
      if (permission == LocationPermission.denied) {
        // Give the user time to read the system permission dialog.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw _permissionPermanentlyDenied;
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const CityLocationException('未开启定位权限，可以重试或手动选择城市。');
      }

      final settings = defaultTargetPlatform == TargetPlatform.iOS
          ? AppleSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: _positionTimeout,
              allowBackgroundLocationUpdates: false,
              pauseLocationUpdatesAutomatically: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: _positionTimeout,
            );
      // The plugin's timeLimit also cancels its native location request.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(
            position.latitude,
            position.longitude,
            locale: const Locale('zh', 'CN'),
          )
          .timeout(_geocodingTimeout);
      for (final placemark in placemarks) {
        final city = cityFromPlacemark(placemark);
        if (city != null) return city;
      }
      throw const CityLocationException('暂时无法识别所在城市，请手动选择。');
    } on CityLocationException {
      rethrow;
    } on LocationServiceDisabledException {
      throw _serviceDisabled;
    } on PermissionDeniedException {
      // Permission can be revoked between checking it and acquiring a fix.
      throw const CityLocationException(
        '定位权限已关闭，请在设置中开启，或手动选择城市。',
        canOpenAppSettings: true,
      );
    } on TimeoutException {
      throw const CityLocationException('定位超时，请重试或手动选择城市。');
    } catch (_) {
      throw const CityLocationException('定位暂时不可用，请重试或手动选择城市。');
    }
  }

  Future<bool> openSettings({required bool appSettings}) async {
    try {
      return await (appSettings
              ? Geolocator.openAppSettings()
              : Geolocator.openLocationSettings())
          .timeout(_platformTimeout);
    } catch (_) {
      return false;
    }
  }

  static const _serviceDisabled = CityLocationException(
    '系统定位服务未开启，请在设置中开启，或手动选择城市。',
    canOpenLocationSettings: true,
  );
  static const _permissionPermanentlyDenied = CityLocationException(
    '定位权限已关闭，请在设置中开启，或手动选择城市。',
    canOpenAppSettings: true,
  );
}

/// Matches the directory's city names, which omit the trailing “市”.
///
/// Native geocoders differ in which field contains the prefecture-level city.
/// Never derive a city from subLocality, street, or a district/county suffix:
/// for example, Beijing's 朝阳区 must not become Liaoning's 朝阳 city.
@visibleForTesting
String? cityFromPlacemark(Placemark placemark) {
  final country = placemark.isoCountryCode?.trim().toUpperCase();
  if (country == 'HK') return '香港';
  if (country == 'MO') return '澳门';

  final administrativeArea = placemark.administrativeArea?.trim();
  final municipality = _municipalityName(administrativeArea);
  if (municipality != null) return municipality;

  // subAdministrativeArea may contain a prefecture while locality identifies
  // a county-level city within it (e.g. 苏州市 / 昆山市).
  final prefecture = _cityName(placemark.subAdministrativeArea);
  if (prefecture != null) return prefecture;
  final locality = _cityName(placemark.locality);
  if (locality != null) return locality;

  // Accept a city-level administrative area, but never a province or region.
  if (administrativeArea?.endsWith('市') ?? false) {
    return _cityName(administrativeArea);
  }
  return null;
}

String? _municipalityName(String? value) {
  if (value == null) return null;
  return switch (value.toLowerCase()) {
    '北京' || '北京市' || 'beijing' => '北京',
    '上海' || '上海市' || 'shanghai' => '上海',
    '天津' || '天津市' || 'tianjin' => '天津',
    '重庆' || '重庆市' || '重慶' || '重慶市' || 'chongqing' => '重庆',
    '香港' || '香港特别行政区' || '香港特別行政區' || 'hong kong' => '香港',
    '澳门' || '澳門' || '澳门特别行政区' || '澳門特別行政區' || 'macao' || 'macau' => '澳门',
    _ => null,
  };
}

String? _cityName(String? value) {
  final city = value?.trim();
  if (city == null || city.length < 2) return null;
  final municipality = _municipalityName(city);
  if (municipality != null) return municipality;
  final isPrefecture = city.endsWith('地区') || city.endsWith('地區');
  if (!RegExp(r'^[\u3400-\u9fff·]+$').hasMatch(city) ||
      (!isPrefecture &&
          RegExp(r'(省|自治区|自治區|特别行政区|特別行政區|区|區|县|縣|镇|鎮|乡|鄉|街道)$')
              .hasMatch(city)) ||
      const {'中国', '中國', '全国', '全國', '市辖区', '市轄區'}.contains(city)) {
    return null;
  }
  return city.endsWith('市') ? city.substring(0, city.length - 1) : city;
}
