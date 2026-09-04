import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';
import 'package:wanpan_diary/features/gyms/brand_screen.dart';

const _pendingDistrictGym = Gym(
  id: 'gym-pending-district',
  name: '香蕉攀岩 凯德天府店',
  city: '成都',
  province: '四川省',
  district: '待核验',
  address: '成都市武侯区天仁路388号凯德天府L5-15铺',
  verified: false,
);

const _knownDistrictGym = Gym(
  id: 'gym-known-district',
  name: '香蕉攀岩 悠方店',
  city: '成都',
  province: '四川省',
  district: '高新区',
  address: '天府大道中段成都悠方购物中心',
  verified: false,
  routeCount: 3,
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
  Future<GymBrandDetail> getBrandStores(String brandId, {String? city}) async =>
      const GymBrandDetail(
        id: 'brand-banana',
        name: '香蕉攀岩',
        stores: [_pendingDistrictGym, _knownDistrictGym],
      );
}

void main() {
  testWidgets(
    'store cards hide placeholder district and keep location detail',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WanpanTheme.light(),
          home: BrandScreen(
            api: _api,
            brandId: 'brand-banana',
            city: '成都',
            gymRepository: _GymRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('待核验'), findsNothing);
      expect(
        find.textContaining('成都 · 成都市武侯区天仁路388号凯德天府L5-15铺 · 0 条线路'),
        findsOneWidget,
      );
      expect(
        find.textContaining('成都 · 高新区 · 天府大道中段成都悠方购物中心 · 3 条线路'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
