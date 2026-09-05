import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanpan_diary/core/models/gym_models.dart';
import 'package:wanpan_diary/core/preferences/gym_selection_store.dart';

const _gym = Gym(
  id: 'shenzhen-store',
  name: '深圳岩馆',
  city: '深圳',
  province: '广东省',
  address: '示例路1号',
  verified: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保存岩馆后跨实例和重新加载本地数据恢复最近选择', () async {
    final store = await GymSelectionStore.load();
    expect(store.gymId, isNull);
    expect(store.hasRegion, isFalse);
    await store.rememberGym(_gym);
    final second = await GymSelectionStore.load();
    expect(second.gymId, _gym.id);
    expect(second.region, (province: '广东省', city: '深圳'));

    final preferences = await SharedPreferences.getInstance();
    final disk = <String, Object>{
      for (final key in preferences.getKeys()) key: preferences.get(key)!,
    };
    SharedPreferences.setMockInitialValues(disk);
    final restarted = await GymSelectionStore.load();
    expect(restarted.gymId, _gym.id);
    expect(restarted.region, (province: '广东省', city: '深圳'));
  });

  test('不同实例交替更新地区和岩馆不覆盖其他字段，全国区别于未选择', () async {
    final first = await GymSelectionStore.load();
    final second = await GymSelectionStore.load();
    await Future.wait([
      first.rememberGym(_gym),
      second.rememberRegion(province: null, city: null),
    ]);
    expect(first.gymId, _gym.id);
    expect(first.hasRegion, isTrue);
    expect(first.region, isNull);
    await second.rememberRegion(province: '广东省', city: '广州');
    await first.clearGym();
    expect(second.gymId, isNull);
    expect(second.region, (province: '广东省', city: '广州'));
    expect(second.hasRegion, isTrue);
  });

  test('无有效城市的门店改为全国，避免被旧地区筛选隐藏', () async {
    final store = await GymSelectionStore.load();
    await store.rememberGym(_gym);
    await store.rememberGym(
      const Gym(
        id: 'pending-region',
        name: '新岩馆',
        city: '待核验',
        province: '',
        address: '',
        verified: false,
      ),
    );
    expect(store.gymId, 'pending-region');
    expect(store.hasRegion, isTrue);
    expect(store.region, isNull);
  });

  test('损坏数据视为无选择并允许后续重新保存', () async {
    for (final value in <Object>[
      '{broken',
      42,
      '[]',
      '{"gymId":42}',
      '{"gymId":"old","region":{"province":"广东省","city":42}}',
    ]) {
      SharedPreferences.setMockInitialValues({'gym_selection_v1': value});
      final store = await GymSelectionStore.load();
      expect(store.gymId, isNull);
      expect(store.hasRegion, isFalse);
      expect(store.region, isNull);
      await store.rememberGym(_gym);
      expect(store.gymId, _gym.id);
    }
  });

  test('新的偏好实例不会被上一轮缓存污染', () async {
    await (await GymSelectionStore.load()).rememberGym(_gym);
    SharedPreferences.setMockInitialValues({});
    final fresh = await GymSelectionStore.load();
    expect(fresh.gymId, isNull);
    expect(fresh.hasRegion, isFalse);
  });

  test('已有首页城市接管旧版全国筛选但保留最近岩馆', () async {
    SharedPreferences.setMockInitialValues({
      'home_city_selection': '成都',
      'gym_selection_v1': '{"gymId":"previous-store","region":null}',
    });
    final store = await GymSelectionStore.load();

    expect(store.hasRegion, isTrue);
    expect(store.region, (province: '', city: '成都'));
    expect(store.gymId, 'previous-store');
  });

  test('手选地区或全国保留到首页下次选择城市', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('home_city_selection', '成都');
    await preferences.setInt('home_city_selection_revision', 1);
    final store = GymSelectionStore(preferences: preferences);

    await store.rememberGym(_gym);
    expect(store.region?.city, '深圳');
    await store.rememberRegion(province: null, city: null);
    expect((await GymSelectionStore.load()).region, isNull);

    // Selecting 成都 again on home is an explicit new city selection.
    await preferences.setInt('home_city_selection_revision', 2);
    expect(store.region, (province: '', city: '成都'));
    expect(store.gymId, _gym.id);

    await store.rememberRegion(province: '广东省', city: '广州');
    expect((await GymSelectionStore.load()).region?.city, '广州');
    await preferences.setString('home_city_selection', '上海');
    expect(store.region, (province: '', city: '上海'));
    expect(store.gymId, _gym.id);
  });

  test('首页明确选择全国时接管旧地区且不清除岩馆', () async {
    final store = await GymSelectionStore.load();
    await store.rememberGym(_gym);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('home_city_selection', '');

    expect(store.hasRegion, isTrue);
    expect(store.region, isNull);
    expect(store.gymId, _gym.id);
    await store.clearGym();
    expect(store.region, isNull);
  });
}
