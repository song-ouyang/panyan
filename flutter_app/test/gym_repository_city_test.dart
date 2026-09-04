import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/gym_repository.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://127.0.0.1:3000/api',
  enableDevelopmentLogin: false,
);

class _RecordingApi extends ApiClient {
  _RecordingApi() : super(config: _config, accessTokenProvider: () => null);

  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPath = path;
    lastQuery = queryParameters;
    return {'id': 'brand-1', 'name': '香蕉攀岩', 'stores': <Object>[]};
  }
}

void main() {
  test('directory city filter is sent only when a city is selected', () async {
    final cityApi = _RecordingApi();
    await GymRepository(cityApi).getDirectory(city: '深圳');
    expect(cityApi.lastPath, '/gyms/directory');
    expect(cityApi.lastQuery, {'city': '深圳'});

    final globalApi = _RecordingApi();
    await GymRepository(globalApi).getDirectory();
    expect(globalApi.lastPath, '/gyms/directory');
    expect(globalApi.lastQuery, isEmpty);
  });

  test(
    'brand directory navigation keeps its city when loading stores',
    () async {
      final api = _RecordingApi();

      await GymRepository(api).getBrandStores('brand-1', city: '深圳');

      expect(api.lastPath, '/gyms/brands/brand-1/stores');
      expect(api.lastQuery, {'city': '深圳'});
    },
  );

  test('shared direct picker can still expand a brand globally', () async {
    final api = _RecordingApi();

    await GymRepository(api).getBrandStores('brand-1');

    expect(api.lastPath, '/gyms/brands/brand-1/stores');
    expect(api.lastQuery, isEmpty);
  });
}
