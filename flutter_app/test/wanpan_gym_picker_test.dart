import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/preferences/gym_selection_store.dart';
import 'package:wanpan_diary/shared/widgets/wanpan_gym_picker.dart';

const _gyms = <Gym>[
  Gym(
    id: 'nanshan',
    name: '香蕉攀岩·南山店',
    city: '深圳',
    province: '广东省',
    district: '南山区',
    brandId: 'banana',
    brandName: '香蕉攀岩',
    address: '南山区示例路1号',
    verified: true,
    routeCount: 19,
  ),
  Gym(
    id: 'baoan',
    name: '香蕉攀岩·宝安店',
    city: '深圳',
    province: '广东省',
    district: '宝安区',
    brandId: 'banana',
    brandName: '香蕉攀岩',
    address: '宝安区示例路3号',
    verified: true,
    routeCount: 8,
  ),
  Gym(
    id: 'solo',
    name: '岩点空间',
    city: '广州',
    province: '广东省',
    district: '天河区',
    address: '天河区示例路9号',
    verified: false,
  ),
  Gym(
    id: 'orbit-tianhe',
    name: '轨迹攀岩·天河店',
    city: '广州',
    province: '广东省',
    district: '天河区',
    brandId: 'orbit',
    brandName: '轨迹攀岩',
    address: '天河区示例路18号',
    verified: true,
    routeCount: 6,
  ),
];

const _regionalGyms = <Gym>[
  ..._gyms,
  Gym(
    id: 'banana-guangzhou',
    name: '香蕉攀岩·广州天河店',
    city: '广州',
    province: '广东省',
    district: '天河区',
    brandId: 'banana',
    brandName: '香蕉攀岩',
    address: '广州天河区示例路5号',
    verified: true,
  ),
  Gym(
    id: 'same-city-a',
    name: '同名城攀岩·甲省店',
    city: '同名市',
    province: '甲省',
    brandId: 'same-city-brand',
    brandName: '同名城攀岩',
    address: '甲省示例路1号',
    verified: true,
  ),
  Gym(
    id: 'same-city-b',
    name: '同名城攀岩·乙省店',
    city: '同名市',
    province: '乙省',
    brandId: 'same-city-brand',
    brandName: '同名城攀岩',
    address: '乙省示例路1号',
    verified: true,
  ),
  Gym(
    id: 'pending-region',
    name: '待确认地区岩馆',
    city: '待核验',
    province: '',
    address: '示例地址',
    verified: false,
  ),
];

Future<void> _openRegionalGymPicker(
  WidgetTester tester, {
  String? selectedGymId,
  GymSelectionStore? selectionStore,
  List<Gym> gyms = _regionalGyms,
  ValueChanged<String?>? onSelected,
  Size size = const Size(430, 932),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: WanpanTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open-test-gym-picker'),
            onPressed: () async {
              final result = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => WanpanGymPickerSheet(
                  gyms: gyms,
                  selectedGymId: selectedGymId,
                  selectionStore: selectionStore,
                ),
              );
              onSelected?.call(result);
            },
            child: const Text('选择测试岩馆'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-test-gym-picker')));
  await tester.pumpAndSettle();
}

Future<void> _selectRegion(WidgetTester tester, String regionKey) async {
  final button = find.byKey(const Key('gym-picker-region-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  final option = find.byKey(Key('gym-region-option-$regionKey'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('首页成都覆盖旧全国并匹配实际省市，最近岩馆保持不变', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '成都市',
      'gym_selection_v1': '{"gymId":"nanshan","region":null}',
    });
    await _openRegionalGymPicker(
      tester,
      selectedGymId: 'nanshan',
      gyms: const [
        ..._regionalGyms,
        Gym(
          id: 'chengdu-youfang',
          name: '香蕉攀岩 悠方店',
          city: '成都',
          province: '四川省',
          address: '成都高新区',
          verified: true,
        ),
      ],
    );

    expect(find.text('成都'), findsOneWidget);
    expect(find.text('香蕉攀岩 悠方店'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsNothing);
    expect((await GymSelectionStore.load()).gymId, 'nanshan');

    await tester.tap(find.byKey(const Key('gym-picker-region-button')));
    await tester.pumpAndSettle();
    final city = find.byKey(const Key('gym-region-option-四川省/成都'));
    expect(city, findsOneWidget);
    expect(
      find.descendant(of: city, matching: find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('首页城市没有岩馆时保留城市并显示空态', (tester) async {
    SharedPreferences.setMockInitialValues({'home_city_selection': '成都'});
    await _openRegionalGymPicker(tester);

    expect(find.text('成都'), findsOneWidget);
    expect(find.text('成都没有找到匹配的岩馆'), findsOneWidget);
    expect(find.text('香蕉攀岩'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('gym model keeps backend-owned brand membership', () {
    final gym = Gym.fromJson({
      'id': 'store-1',
      'name': '香蕉攀岩·南山店',
      'city': '深圳',
      'province': '广东省',
      'district': '南山区',
      'brand_id': 'brand-1',
      'brand_name': '香蕉攀岩',
      'address': '示例路1号',
      'verified': true,
      'route_count': 3,
    });

    expect(gym.brandId, 'brand-1');
    expect(gym.brandName, '香蕉攀岩');
  });

  testWidgets('stores are grouped under one brand and expanded on demand', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: const Scaffold(
          body: WanpanGymPickerSheet(gyms: _gyms, selectedGymId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 个岩馆品牌 · 选择后再进入具体门店'), findsOneWidget);
    expect(find.text('香蕉攀岩'), findsOneWidget);
    expect(find.text('2 家门店'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsNothing);
    expect(find.text('香蕉攀岩·宝安店'), findsNothing);

    await tester.tap(find.text('香蕉攀岩'));
    await tester.pumpAndSettle();

    expect(find.text('香蕉攀岩·南山店'), findsOneWidget);
    expect(find.text('香蕉攀岩·宝安店'), findsOneWidget);
  });

  testWidgets('只有一家门店的品牌仍先展开品牌层级', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: WanpanTheme.light(),
        home: const Scaffold(
          body: WanpanGymPickerSheet(gyms: _gyms, selectedGymId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('轨迹攀岩'), findsOneWidget);
    expect(find.text('轨迹攀岩·天河店'), findsNothing);
    expect(find.text('1 家门店'), findsOneWidget);

    await tester.tap(find.text('轨迹攀岩'));
    await tester.pumpAndSettle();

    expect(find.text('轨迹攀岩·天河店'), findsOneWidget);
    expect(find.byType(AnimatedSize), findsNothing);
  });

  testWidgets(
    'searching a store keeps the brand context and narrows children',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: WanpanTheme.light(),
          home: const Scaffold(
            body: WanpanGymPickerSheet(gyms: _gyms, selectedGymId: null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '宝安');
      await tester.pumpAndSettle();

      expect(find.text('香蕉攀岩'), findsOneWidget);
      expect(find.text('香蕉攀岩·宝安店'), findsOneWidget);
      expect(find.text('香蕉攀岩·南山店'), findsNothing);
      expect(find.text('岩点空间'), findsNothing);
    },
  );

  testWidgets('地区筛选只显示品牌在当地的门店与数量，全国可恢复跨城门店', (tester) async {
    await _openRegionalGymPicker(tester);
    final search = find.byKey(const Key('gym-picker-search'));
    await tester.enterText(search, '香蕉');
    await tester.pumpAndSettle();

    expect(find.text('3 家门店'), findsOneWidget);
    expect(find.text('香蕉攀岩·广州天河店'), findsOneWidget);

    await _selectRegion(tester, '广东省/深圳');

    expect(find.byType(WanpanGymPickerSheet), findsOneWidget);
    expect(find.byKey(const Key('gym-region-search')), findsNothing);
    expect(tester.widget<TextField>(search).controller!.text, '香蕉');
    expect(find.text('2 家门店'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsOneWidget);
    expect(find.text('香蕉攀岩·宝安店'), findsOneWidget);
    expect(find.text('香蕉攀岩·广州天河店'), findsNothing);

    await _selectRegion(tester, 'national');

    expect(tester.widget<TextField>(search).controller!.text, '香蕉');
    expect(find.text('3 家门店'), findsOneWidget);
    expect(find.text('香蕉攀岩·广州天河店'), findsOneWidget);
  });

  testWidgets('关键词与地区求交，清空关键词保留地区，门店数跟随搜索结果', (tester) async {
    await _openRegionalGymPicker(tester);
    await _selectRegion(tester, '广东省/深圳');
    final search = find.byKey(const Key('gym-picker-search'));

    await tester.enterText(search, '宝安');
    await tester.pumpAndSettle();
    expect(find.text('1 家门店'), findsOneWidget);
    expect(find.text('香蕉攀岩·宝安店'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsNothing);

    await tester.enterText(search, '天河');
    await tester.pumpAndSettle();
    expect(find.text('深圳没有找到匹配的岩馆'), findsOneWidget);
    expect(find.text('香蕉攀岩·广州天河店'), findsNothing);
    expect(find.text('轨迹攀岩'), findsNothing);

    await tester.tap(find.byTooltip('清空关键词'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('深圳'), findsOneWidget);
    expect(find.text('2 家门店'), findsOneWidget);
    expect(find.text('1 个岩馆品牌 · 选择后再进入具体门店'), findsOneWidget);
    expect(find.text('轨迹攀岩'), findsNothing);
  });

  testWidgets('已有门店预选省市，同名城市不混淆且选店返回正确 ID', (tester) async {
    String? selected;
    await _openRegionalGymPicker(
      tester,
      selectedGymId: 'same-city-a',
      onSelected: (value) => selected = value,
    );

    expect(find.text('同名市'), findsOneWidget);
    expect(find.text('同名城攀岩·甲省店'), findsOneWidget);
    expect(find.text('同名城攀岩·乙省店'), findsNothing);
    expect(find.text('1 家门店'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gym-picker-region-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gym-region-option-甲省/同名市')), findsOneWidget);
    final otherRegion = find.byKey(const Key('gym-region-option-乙省/同名市'));
    expect(otherRegion, findsOneWidget);
    await tester.tap(otherRegion);
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('同名城攀岩·甲省店'), findsNothing);
    expect(find.text('同名城攀岩·乙省店'), findsOneWidget);
    await tester.tap(find.text('同名城攀岩·乙省店'));
    await tester.pumpAndSettle();

    expect(selected, 'same-city-b');
    expect(find.byType(WanpanGymPickerSheet), findsNothing);
  });

  testWidgets('待核验地区不成为筛选项，地区搜索支持省份且不限制为当前岩馆关键词', (tester) async {
    await _openRegionalGymPicker(tester, selectedGymId: 'pending-region');
    expect(find.text('全国'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gym-picker-search')), '香蕉');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gym-picker-region-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gym-region-option-/待核验')), findsNothing);
    expect(find.byKey(const Key('gym-region-option-甲省/同名市')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gym-region-search')), '广东');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gym-region-option-广东省/深圳')), findsOneWidget);
    expect(find.byKey(const Key('gym-region-option-广东省/广州')), findsOneWidget);
    expect(find.byKey(const Key('gym-region-option-甲省/同名市')), findsNothing);
    await tester.tap(find.byKey(const Key('gym-region-option-广东省/广州')));
    await tester.pumpAndSettle();

    expect(find.text('1 家门店'), findsOneWidget);
    expect(find.text('香蕉攀岩·广州天河店'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsNothing);
  });

  testWidgets('小屏大字号和键盘下可滚动完成地区与门店选择', (tester) async {
    String? selected;
    await _openRegionalGymPicker(
      tester,
      size: const Size(320, 568),
      textScale: 1.35,
      onSelected: (value) => selected = value,
    );
    tester.view.viewInsets = FakeViewPadding(
      bottom: 230 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const Key('gym-picker-region-button')),
    );
    await tester.tap(find.byKey(const Key('gym-picker-region-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final regionSearch = find.byKey(const Key('gym-region-search'));
    await tester.ensureVisible(regionSearch);
    await tester.enterText(regionSearch, '深圳');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final shenzhen = find.byKey(const Key('gym-region-option-广东省/深圳'));
    await tester.ensureVisible(shenzhen);
    await tester.tap(shenzhen);
    await tester.pumpAndSettle();

    final gymSearch = find.byKey(const Key('gym-picker-search'));
    await tester.ensureVisible(gymSearch);
    await tester.enterText(gymSearch, '宝安');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final store = find.text('香蕉攀岩·宝安店');
    await tester.ensureVisible(store);
    await tester.pumpAndSettle();
    await tester.tap(store);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selected, 'baoan');
  });

  testWidgets('关闭重开恢复手选地区，手选全国优先于已选岩馆地区', (tester) async {
    final store = await GymSelectionStore.load();
    await store.rememberGym(_gyms.first);
    await _openRegionalGymPicker(tester, selectedGymId: 'nanshan');
    expect(find.text('深圳'), findsOneWidget);

    await _selectRegion(tester, '广东省/广州');
    expect((await GymSelectionStore.load()).region?.city, '广州');
    await tester.ensureVisible(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-test-gym-picker')));
    await tester.pumpAndSettle();
    expect(find.text('广州'), findsOneWidget);
    expect(find.text('香蕉攀岩·南山店'), findsNothing);
    expect(store.gymId, 'nanshan');

    await _selectRegion(tester, 'national');
    await tester.ensureVisible(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-test-gym-picker')));
    await tester.pumpAndSettle();
    expect(find.text('全国'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gym-picker-search')), '香蕉');
    await tester.pumpAndSettle();
    expect(find.text('香蕉攀岩·南山店'), findsOneWidget);
    expect(store.hasRegion, isTrue);
    expect(store.region, isNull);
    expect(store.gymId, 'nanshan');
  });

  testWidgets('选店保存岩馆与地区，重建选择器仍能读取', (tester) async {
    String? selected;
    await _openRegionalGymPicker(
      tester,
      onSelected: (value) => selected = value,
    );
    await tester.enterText(find.byKey(const Key('gym-picker-search')), '宝安');
    await tester.pumpAndSettle();
    await tester.tap(find.text('香蕉攀岩·宝安店'));
    await tester.pumpAndSettle();
    expect(selected, 'baoan');

    final restored = await GymSelectionStore.load();
    expect(restored.gymId, 'baoan');
    expect(restored.region, (province: '广东省', city: '深圳'));
    await tester.tap(find.byKey(const Key('open-test-gym-picker')));
    await tester.pumpAndSettle();
    expect(find.text('深圳'), findsOneWidget);
    expect(find.text('1 个岩馆品牌 · 选择后再进入具体门店'), findsOneWidget);
  });

  testWidgets('存储失败仍可筛选地区和返回所选岩馆', (tester) async {
    String? selected;
    final store = _FailingGymSelectionStore(
      preferences: await SharedPreferences.getInstance(),
    );
    await _openRegionalGymPicker(
      tester,
      selectionStore: store,
      onSelected: (value) => selected = value,
    );
    await _selectRegion(tester, '广东省/深圳');
    expect(find.text('深圳'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gym-picker-search')), '宝安');
    await tester.pumpAndSettle();
    await tester.tap(find.text('香蕉攀岩·宝安店'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selected, 'baoan');
  });
}

class _FailingGymSelectionStore extends GymSelectionStore {
  _FailingGymSelectionStore({required super.preferences});

  @override
  bool get hasRegion => throw StateError('Storage unavailable');

  @override
  Future<void> rememberGym(Gym gym) async =>
      throw StateError('Storage unavailable');

  @override
  Future<void> rememberRegion({
    required String? province,
    required String? city,
  }) async => throw StateError('Storage unavailable');
}
