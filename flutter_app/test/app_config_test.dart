import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';

void main() {
  test('a build without dart-defines uses the production API', () {
    final config = AppConfig.fromEnvironment();

    expect(config.environment, AppEnvironment.production);
    expect(config.apiBaseUrl, 'https://panyan-api.gblh.cloud/api');
    expect(config.enableDevelopmentLogin, isFalse);
  });
}
