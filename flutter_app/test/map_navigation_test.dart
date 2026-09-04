import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/features/gyms/map_navigation.dart';

const _target = MapNavigationTarget(
  name: '香蕉攀岩 凯德 天府店',
  city: '成都',
  address: '成都市武侯区天仁路388号 凯德天府L5-15铺',
  latitude: 30.602869,
  longitude: 104.069028,
);

void main() {
  test('builds documented iOS map URIs with encoded destination data', () {
    const launcher = DeviceMapNavigationLauncher(
      platform: TargetPlatform.iOS,
      tencentMapKey: 'tencent-key',
    );

    final amap = launcher.uriFor(MapNavigationApp.amap, _target)!;
    expect(amap.scheme, 'iosamap');
    expect(amap.host, 'navi');
    expect(amap.queryParameters['poiname'], _target.name);
    expect(amap.queryParameters['lat'], '30.602869');
    expect(amap.queryParameters['lon'], '104.069028');
    expect(amap.toString(), contains('%20'));
    expect(amap.toString(), isNot(contains('+')));

    final tencent = launcher.uriFor(MapNavigationApp.tencent, _target)!;
    expect(tencent.scheme, 'qqmap');
    expect(tencent.queryParameters['fromcoord'], 'CurrentLocation');
    expect(tencent.queryParameters['tocoord'], '30.602869,104.069028');
    expect(tencent.queryParameters['referer'], 'tencent-key');

    final baidu = launcher.uriFor(MapNavigationApp.baidu, _target)!;
    expect(baidu.scheme, 'baidumap');
    expect(baidu.queryParameters['location'], '30.602869,104.069028');
    expect(baidu.queryParameters['query'], _target.name);
    expect(baidu.queryParameters['coord_type'], 'gcj02');
    expect(baidu.queryParameters['src'], 'ios.wanpan.wanpanDiary');

    final system = launcher.uriFor(MapNavigationApp.system, _target)!;
    expect(system.host, 'maps.apple.com');
    expect(system.queryParameters['daddr'], '30.602869,104.069028');
  });

  test(
    'builds Android navigation URIs and omits unconfigured Tencent',
    () async {
      final checked = <Uri>[];
      final launcher = DeviceMapNavigationLauncher(
        platform: TargetPlatform.android,
        canOpenUrl: (uri) async {
          checked.add(uri);
          return uri.scheme == 'androidamap' || uri.scheme == 'baidumap';
        },
      );

      final apps = await launcher.availableApps(_target);

      expect(apps, [MapNavigationApp.amap, MapNavigationApp.baidu]);
      expect(checked.map((uri) => uri.scheme), [
        'androidamap',
        'baidumap',
        'geo',
      ]);
      expect(launcher.uriFor(MapNavigationApp.tencent, _target), isNull);
      expect(
        launcher
            .uriFor(MapNavigationApp.amap, _target)!
            .queryParameters['sourceApplication'],
        '完攀日记',
      );
    },
  );

  test('falls back to a web route when no native map is available', () async {
    final launcher = DeviceMapNavigationLauncher(
      platform: TargetPlatform.android,
      canOpenUrl: (_) async => false,
    );

    expect(await launcher.availableApps(_target), [MapNavigationApp.web]);
    final web = launcher.uriFor(MapNavigationApp.web, _target)!;
    expect(web.scheme, 'https');
    expect(web.host, 'api.map.baidu.com');
    expect(web.queryParameters['mode'], 'driving');
    expect(web.queryParameters['region'], '成都');
  });

  test('uses name and address when coordinates are missing', () {
    const target = MapNavigationTarget(
      name: '示例岩馆',
      city: '成都',
      address: '武侯区示例路1号',
    );
    const ios = DeviceMapNavigationLauncher(platform: TargetPlatform.iOS);
    const android = DeviceMapNavigationLauncher(
      platform: TargetPlatform.android,
    );
    const tencent = DeviceMapNavigationLauncher(
      platform: TargetPlatform.android,
      tencentMapKey: 'tencent-key',
    );
    expect(target.hasCoordinates, isFalse);
    expect(
      ios.uriFor(MapNavigationApp.amap, target)!.queryParameters['dname'],
      '示例岩馆 成都 武侯区示例路1号',
    );
    expect(target.searchText, '示例岩馆 成都 武侯区示例路1号');
    final androidAmap = android.uriFor(MapNavigationApp.amap, target)!;
    expect(androidAmap.scheme, 'androidamap');
    expect(androidAmap.host, 'poi');
    expect(androidAmap.queryParameters['keywords'], target.searchText);

    final tencentSearch = tencent.uriFor(MapNavigationApp.tencent, target)!;
    expect(tencentSearch.path, '/search');
    expect(tencentSearch.queryParameters['keyword'], target.searchText);
    expect(tencentSearch.queryParameters['region'], target.city);
    expect(tencentSearch.queryParameters['referer'], 'tencent-key');

    final baidu = android.uriFor(MapNavigationApp.baidu, target)!;
    expect(baidu.path, '/direction');
    expect(baidu.queryParameters['destination'], target.searchText);
    expect(baidu.queryParameters['origin'], '我的位置');
    expect(
      android
          .uriFor(MapNavigationApp.web, target)!
          .queryParameters['destination'],
      '示例岩馆 成都 武侯区示例路1号',
    );
  });

  test('avoids duplicate city text and rejects unusable coordinates', () {
    const cityInAddress = MapNavigationTarget(
      name: '示例岩馆',
      city: '成都',
      address: '成都市武侯区示例路1号',
    );
    const zeroCoordinates = MapNavigationTarget(
      name: '零点岩馆',
      city: '成都',
      address: '高新区示例路2号',
      latitude: 0,
      longitude: 0,
    );
    const invalidCoordinates = MapNavigationTarget(
      name: '越界岩馆',
      city: '成都',
      address: '锦江区示例路3号',
      latitude: 91,
      longitude: 181,
    );
    const android = DeviceMapNavigationLauncher(
      platform: TargetPlatform.android,
    );

    expect(cityInAddress.searchText, '示例岩馆 成都市武侯区示例路1号');
    expect(zeroCoordinates.hasCoordinates, isFalse);
    expect(invalidCoordinates.hasCoordinates, isFalse);
    expect(
      android
          .uriFor(MapNavigationApp.amap, zeroCoordinates)!
          .queryParameters['keywords'],
      '零点岩馆 成都 高新区示例路2号',
    );
    expect(
      android.uriFor(MapNavigationApp.baidu, invalidCoordinates)!.path,
      '/direction',
    );
  });

  test('launch failures and exceptions remain recoverable', () async {
    final returnedFalse = DeviceMapNavigationLauncher(
      platform: TargetPlatform.iOS,
      openUrl: (_) async => false,
    );
    final threw = DeviceMapNavigationLauncher(
      platform: TargetPlatform.iOS,
      openUrl: (_) => throw StateError('unavailable'),
    );

    expect(await returnedFalse.open(MapNavigationApp.amap, _target), isFalse);
    expect(await threw.open(MapNavigationApp.baidu, _target), isFalse);
  });
}
