import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';

void main() {
  test('a build without dart-defines uses the production API', () {
    final config = AppConfig.fromEnvironment();

    expect(config.environment, AppEnvironment.production);
    expect(config.apiBaseUrl, 'https://panyan-api.gblh.cloud/api');
    expect(config.enableDevelopmentLogin, isFalse);
  });

  group('official invitation URL', () {
    test('default invitation opens the official website download section', () {
      final config = AppConfig.fromEnvironment();

      expect(config.inviteUrl.origin, AppConfig.defaultShareBaseUrl);
      expect(config.inviteUrl.path, '/');
      expect(config.inviteUrl.fragment, 'download');
      expect(config.inviteUrl.hasQuery, isFalse);
    });

    test(
      'uses the configured website origin and normalizes trailing slash',
      () {
        const config = AppConfig(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://api.example.com/api',
          enableDevelopmentLogin: false,
          shareBaseUrl: ' https://wanpan.example.com/ ',
        );

        expect(
          config.inviteUrl,
          Uri.parse('https://wanpan.example.com/#download'),
        );
      },
    );

    test('rejects invalid invitation origins before generating a QR code', () {
      for (final origin in [
        'http://wanpan.example.com',
        'https://localhost',
        'https://wanpan.example.com/unrelated',
        'https://wanpan.example.com/?token=private',
        'https://wanpan.example.com/#other',
        'https://user:password@wanpan.example.com',
      ]) {
        final config = AppConfig(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://api.example.com/api',
          enableDevelopmentLogin: false,
          shareBaseUrl: origin,
        );
        expect(() => config.inviteUrl, throwsArgumentError, reason: origin);
      }
    });
  });

  group('release build guardrails', () {
    test('force production and ignore stale development defines', () {
      final config = AppConfig.resolveForBuild(
        isReleaseMode: true,
        isAndroid: false,
        appEnvironment: 'development',
        apiBaseUrl: 'http://127.0.0.1:3000/api',
        productionApiBaseUrl: 'https://api.example.com/api/',
        enableDevelopmentLogin: true,
      );

      expect(config.environment, AppEnvironment.production);
      expect(config.apiBaseUrl, 'https://api.example.com/api');
      expect(config.enableDevelopmentLogin, isFalse);
    });

    test('rejects non-HTTPS and local production URLs', () {
      const invalidUrls = [
        'http://api.example.com/api',
        'https://localhost:3000/api',
        'https://127.0.0.1:3000/api',
        'https://10.0.2.2:3000/api',
      ];

      for (final url in invalidUrls) {
        expect(
          () => AppConfig.resolveForBuild(
            isReleaseMode: true,
            isAndroid: false,
            appEnvironment: 'production',
            apiBaseUrl: '',
            productionApiBaseUrl: url,
            enableDevelopmentLogin: false,
          ),
          throwsArgumentError,
          reason: url,
        );
      }
    });
  });

  test('production configuration never consumes the generic API override', () {
    final config = AppConfig.resolveForBuild(
      isReleaseMode: false,
      isAndroid: false,
      appEnvironment: 'production',
      apiBaseUrl: 'http://127.0.0.1:3000/api',
      productionApiBaseUrl: 'https://api.example.com/api',
      enableDevelopmentLogin: true,
    );

    expect(config.environment, AppEnvironment.production);
    expect(config.apiBaseUrl, 'https://api.example.com/api');
    expect(config.enableDevelopmentLogin, isFalse);
  });

  group('debug development configuration', () {
    test('keeps an explicit local override and development login', () {
      final config = AppConfig.resolveForBuild(
        isReleaseMode: false,
        isAndroid: false,
        appEnvironment: 'development',
        apiBaseUrl: 'http://192.168.1.8:3000/api/',
        productionApiBaseUrl: 'https://api.example.com/api',
        enableDevelopmentLogin: true,
      );

      expect(config.environment, AppEnvironment.development);
      expect(config.apiBaseUrl, 'http://192.168.1.8:3000/api');
      expect(config.enableDevelopmentLogin, isTrue);
    });

    test('uses the platform local address without an override', () {
      final ios = AppConfig.resolveForBuild(
        isReleaseMode: false,
        isAndroid: false,
        appEnvironment: 'development',
        apiBaseUrl: '',
        productionApiBaseUrl: 'https://api.example.com/api',
        enableDevelopmentLogin: false,
      );
      final android = AppConfig.resolveForBuild(
        isReleaseMode: false,
        isAndroid: true,
        appEnvironment: 'development',
        apiBaseUrl: '',
        productionApiBaseUrl: 'https://api.example.com/api',
        enableDevelopmentLogin: false,
      );

      expect(ios.apiBaseUrl, 'http://127.0.0.1:3000/api');
      expect(android.apiBaseUrl, 'http://10.0.2.2:3000/api');
    });
  });
}
