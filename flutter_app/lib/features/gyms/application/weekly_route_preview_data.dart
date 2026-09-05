import '../../../shared/app_assets.dart';

// Temporary home preview. Set USE_WEEKLY_ROUTE_MOCKS=false when the real
// weekly endpoint and route information are ready.
const useWeeklyRouteMocks = bool.fromEnvironment(
  'USE_WEEKLY_ROUTE_MOCKS',
  defaultValue: true,
);

class WeeklyGymPreview {
  const WeeklyGymPreview({
    required this.id,
    required this.name,
    required this.storeName,
    required this.coverAsset,
    this.gymId,
    this.brandId,
  });

  final String id;
  final String name;
  final String storeName;
  final String coverAsset;
  final String? gymId;
  final String? brandId;
  String get city => '成都';
}

// IDs identify real Chengdu stores or brands in the existing gym directory.
const _chengduGyms = [
  WeeklyGymPreview(
    id: 'banana',
    name: '香蕉攀岩',
    storeName: '凯德天府店',
    gymId: '71330197-04ac-4d15-8db6-b35a490088d4',
    coverAsset: AppAssets.routeMapCat,
  ),
  WeeklyGymPreview(
    id: 'qiushan',
    name: '丘山攀岩',
    storeName: 'CyPARK店',
    gymId: 'fe86c13b-9f60-4f20-90fd-acdbc5a37ccb',
    coverAsset: AppAssets.routeReviewCat,
  ),
  WeeklyGymPreview(
    id: 'panda',
    name: '熊猫攀岩',
    storeName: '',
    brandId: 'b0104aad-3abe-4830-9f53-3d85c881b6be',
    coverAsset: AppAssets.mascotCelebrate,
  ),
];

List<WeeklyGymPreview> weeklyGymPreviewData({String? city}) {
  final place = city?.trim();
  if (place == null || place.isEmpty || place == '成都' || place == '成都市') {
    return _chengduGyms;
  }
  return const [];
}
