import 'dart:io';

enum AppEnvironment { development, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.enableDevelopmentLogin,
    this.enableAppleLogin = false,
  });

  static const String productionApiBaseUrl = String.fromEnvironment(
    'PRODUCTION_API_BASE_URL',
    defaultValue: 'https://panyan-api.gblh.cloud/api',
  );

  static AppConfig fromEnvironment() {
    const environmentValue = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const overrideUrl = String.fromEnvironment('API_BASE_URL');
    const developmentLogin = bool.fromEnvironment(
      'ENABLE_DEV_LOGIN',
      defaultValue: false,
    );
    const appleLogin = bool.fromEnvironment(
      'ENABLE_APPLE_LOGIN',
      defaultValue: false,
    );
    final environment = environmentValue.toLowerCase() == 'production'
        ? AppEnvironment.production
        : AppEnvironment.development;
    final platformLocalUrl = Platform.isAndroid
        ? 'http://10.0.2.2:3000/api'
        : 'http://127.0.0.1:3000/api';

    return AppConfig(
      environment: environment,
      apiBaseUrl: _normalizeBaseUrl(
        overrideUrl.isNotEmpty
            ? overrideUrl
            : environment == AppEnvironment.production
            ? productionApiBaseUrl
            : platformLocalUrl,
      ),
      enableDevelopmentLogin:
          environment == AppEnvironment.development && developmentLogin,
      enableAppleLogin: appleLogin,
    );
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool enableDevelopmentLogin;
  final bool enableAppleLogin;

  bool get isProduction => environment == AppEnvironment.production;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
