import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

typedef MapUriAction = Future<bool> Function(Uri uri);

Future<bool> _canOpenMapUri(Uri uri) => canLaunchUrl(uri);

Future<bool> _openMapUri(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

@immutable
class MapNavigationTarget {
  const MapNavigationTarget({
    required this.name,
    required this.city,
    required this.address,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String city;
  final String address;
  final double? latitude;
  final double? longitude;

  String get searchText {
    final gymName = name.trim();
    final gymCity = city.trim();
    final gymAddress = address.trim();
    final identity = '$gymName $gymAddress';
    return <String>[
      gymName,
      if (gymCity.isNotEmpty && !identity.contains(gymCity)) gymCity,
      gymAddress,
    ].where((part) => part.isNotEmpty).join(' ');
  }

  bool get hasCoordinates {
    final lat = latitude;
    final lng = longitude;
    return lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180 &&
        (lat != 0 || lng != 0);
  }
}

enum MapNavigationApp { amap, tencent, baidu, system, web }

extension MapNavigationAppLabel on MapNavigationApp {
  String label(TargetPlatform platform) => switch (this) {
    MapNavigationApp.amap => '高德地图',
    MapNavigationApp.tencent => '腾讯地图',
    MapNavigationApp.baidu => '百度地图',
    MapNavigationApp.system when platform == TargetPlatform.iOS => 'Apple 地图',
    MapNavigationApp.system => '系统地图',
    MapNavigationApp.web => '网页地图',
  };
}

abstract interface class MapNavigationLauncher {
  TargetPlatform get currentPlatform;

  Future<List<MapNavigationApp>> availableApps(MapNavigationTarget target);

  Future<bool> open(MapNavigationApp app, MapNavigationTarget target);
}

class DeviceMapNavigationLauncher implements MapNavigationLauncher {
  const DeviceMapNavigationLauncher({
    this.platform,
    this.tencentMapKey = configuredTencentMapKey,
    this.canOpenUrl = _canOpenMapUri,
    this.openUrl = _openMapUri,
  });

  static const configuredTencentMapKey = String.fromEnvironment(
    'TENCENT_MAP_KEY',
  );

  final TargetPlatform? platform;
  final String tencentMapKey;
  final MapUriAction canOpenUrl;
  final MapUriAction openUrl;

  @override
  TargetPlatform get currentPlatform => platform ?? defaultTargetPlatform;

  bool get _supportsNativeMaps =>
      currentPlatform == TargetPlatform.iOS ||
      currentPlatform == TargetPlatform.android;

  @override
  Future<List<MapNavigationApp>> availableApps(
    MapNavigationTarget target,
  ) async {
    if (!_supportsNativeMaps) return const [MapNavigationApp.web];

    final candidates = <MapNavigationApp>[
      MapNavigationApp.amap,
      if (tencentMapKey.trim().isNotEmpty) MapNavigationApp.tencent,
      MapNavigationApp.baidu,
      MapNavigationApp.system,
    ];
    final installed = await Future.wait(
      candidates.map((app) async {
        final uri = uriFor(app, target);
        if (uri == null) return null;
        try {
          return await canOpenUrl(uri) ? app : null;
        } catch (_) {
          return null;
        }
      }),
    );
    final apps = installed.whereType<MapNavigationApp>().toList();
    return apps.isEmpty ? const [MapNavigationApp.web] : apps;
  }

  @override
  Future<bool> open(MapNavigationApp app, MapNavigationTarget target) async {
    final uri = uriFor(app, target);
    if (uri == null) return false;
    try {
      return await openUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Builds documented map-provider URI schemes. Directory coordinates are
  /// treated as GCJ-02; the destination name is also carried so users can
  /// verify the selected POI before starting navigation.
  Uri? uriFor(MapNavigationApp app, MapNavigationTarget target) =>
      switch (app) {
        MapNavigationApp.amap => _amapUri(target),
        MapNavigationApp.tencent => _tencentUri(target),
        MapNavigationApp.baidu => _baiduUri(target),
        MapNavigationApp.system => _systemUri(target),
        MapNavigationApp.web => _webUri(target),
      };

  Uri? _amapUri(MapNavigationTarget target) {
    if (target.hasCoordinates) {
      final scheme = currentPlatform == TargetPlatform.iOS
          ? 'iosamap://navi'
          : 'androidamap://navi';
      return _customUri(scheme, {
        'sourceApplication': '完攀日记',
        'poiname': target.name.trim(),
        'lat': _coordinate(target.latitude!),
        'lon': _coordinate(target.longitude!),
        'dev': '0',
        'style': '0',
      });
    }
    if (target.searchText.isEmpty) return null;
    if (currentPlatform == TargetPlatform.iOS) {
      return _customUri('iosamap://path', {
        'sourceApplication': '完攀日记',
        'dname': target.searchText,
        'dev': '0',
        't': '0',
        'm': '0',
      });
    }
    if (currentPlatform == TargetPlatform.android) {
      // Dart normalizes URI authorities to lowercase. Use AMap's all-lowercase
      // POI endpoint so the documented camel-cased keywordNavi authority is
      // not silently changed before Android receives it.
      return _customUri('androidamap://poi', {
        'sourceApplication': '完攀日记',
        'keywords': target.searchText,
        'dev': '0',
      });
    }
    return null;
  }

  Uri? _tencentUri(MapNavigationTarget target) {
    final key = tencentMapKey.trim();
    if (key.isEmpty) return null;
    if (target.hasCoordinates) {
      return _customUri('qqmap://map/routeplan', {
        'type': 'drive',
        'fromcoord': 'CurrentLocation',
        'to': target.name.trim(),
        'tocoord':
            '${_coordinate(target.latitude!)},${_coordinate(target.longitude!)}',
        'referer': key,
      });
    }
    if (target.searchText.isEmpty) return null;
    return _customUri('qqmap://map/search', {
      'keyword': target.searchText,
      'region': target.city.trim(),
      'referer': key,
    });
  }

  Uri? _baiduUri(MapNavigationTarget target) {
    final source = currentPlatform == TargetPlatform.iOS
        ? 'ios.wanpan.wanpanDiary'
        : 'andr.wanpan.wanpanDiary';
    if (target.hasCoordinates) {
      return _customUri('baidumap://map/navi', {
        'location':
            '${_coordinate(target.latitude!)},${_coordinate(target.longitude!)}',
        'query': target.name.trim(),
        'coord_type': 'gcj02',
        'type': 'DEFAULT',
        'src': source,
      });
    }
    if (target.searchText.isEmpty) return null;
    return _customUri('baidumap://map/direction', {
      'origin': '我的位置',
      'destination': target.searchText,
      'coord_type': 'gcj02',
      'mode': 'driving',
      'region': target.city.trim(),
      'src': source,
    });
  }

  Uri _systemUri(MapNavigationTarget target) {
    if (currentPlatform == TargetPlatform.iOS) {
      return Uri.https('maps.apple.com', '/', {
        'daddr': target.hasCoordinates
            ? '${_coordinate(target.latitude!)},${_coordinate(target.longitude!)}'
            : target.searchText,
        'q': target.name.trim(),
        'dirflg': 'd',
      });
    }
    final location = target.hasCoordinates
        ? '${_coordinate(target.latitude!)},${_coordinate(target.longitude!)}'
        : '0,0';
    final query = target.hasCoordinates
        ? '$location(${target.name.trim()})'
        : target.searchText;
    return Uri.parse('geo:$location?${_encodeQuery({'q': query})}');
  }

  Uri _webUri(MapNavigationTarget target) {
    final destination = target.hasCoordinates
        ? 'name:${target.name.trim()}|latlng:${_coordinate(target.latitude!)},${_coordinate(target.longitude!)}'
        : target.searchText;
    return Uri.https('api.map.baidu.com', '/direction', {
      'origin': '我的位置',
      'destination': destination,
      'mode': 'driving',
      'coord_type': 'gcj02',
      'region': target.city.trim(),
      'output': 'html',
      'src': 'webapp.wanpan.wanpanDiary',
    });
  }
}

Uri _customUri(String base, Map<String, String> parameters) =>
    Uri.parse('$base?${_encodeQuery(parameters)}');

String _encodeQuery(Map<String, String> parameters) => parameters.entries
    .where((entry) => entry.value.isNotEmpty)
    .map(
      (entry) =>
          '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
    )
    .join('&');

String _coordinate(double value) => value.toStringAsFixed(6);
