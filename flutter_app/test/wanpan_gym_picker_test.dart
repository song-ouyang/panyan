import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/app/wanpan_theme.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
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

void main() {
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
}
