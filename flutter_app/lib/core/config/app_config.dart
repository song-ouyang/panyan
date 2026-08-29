import 'dart:io';

enum AppEnvironment { development, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.enableDevelopmentLogin,
    this.wechatMobileAppId = '',
    this.wechatUniversalLink = '',
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
    const wechatMobileAppId = String.fromEnvironment('WECHAT_MOBILE_APP_ID');
    const wechatUniversalLink = String.fromEnvironment('WECHAT_UNIVERSAL_LINK');
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
      wechatMobileAppId: wechatMobileAppId.trim(),
      wechatUniversalLink: wechatUniversalLink.trim(),
    );
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool enableDevelopmentLogin;
  final String wechatMobileAppId;
  final String wechatUniversalLink;

  bool get isProduction => environment == AppEnvironment.production;
  bool get hasWechatMobileConfig =>
      wechatMobileAppId.isNotEmpty && wechatUniversalLink.isNotEmpty;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
