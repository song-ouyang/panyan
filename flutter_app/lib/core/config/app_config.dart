import 'dart:io';

import 'package:flutter/foundation.dart';

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
      defaultValue: 'production',
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
    return resolveForBuild(
      isReleaseMode: kReleaseMode,
      isAndroid: Platform.isAndroid,
      appEnvironment: environmentValue,
      apiBaseUrl: overrideUrl,
      productionApiBaseUrl: productionApiBaseUrl,
      enableDevelopmentLogin: developmentLogin,
      enableAppleLogin: appleLogin,
    );
  }

  /// Pure build-configuration resolver used by [fromEnvironment] and tests.
  ///
  /// Release builds always resolve to production, only accept the dedicated
  /// production URL, and never expose development login. This prevents stale
  /// Xcode/Gradle dart-defines from leaking local development settings into an
  /// archived app.
  static AppConfig resolveForBuild({
    required bool isReleaseMode,
    required bool isAndroid,
    required String appEnvironment,
    required String apiBaseUrl,
    required String productionApiBaseUrl,
    required bool enableDevelopmentLogin,
    bool enableAppleLogin = false,
  }) {
    final requestedDevelopment =
        appEnvironment.trim().toLowerCase() == 'development';
    final environment = !isReleaseMode && requestedDevelopment
        ? AppEnvironment.development
        : AppEnvironment.production;

    final resolvedUrl = environment == AppEnvironment.production
        ? _validatedProductionUrl(productionApiBaseUrl)
        : _normalizeBaseUrl(
            apiBaseUrl.trim().isNotEmpty
                ? apiBaseUrl
                : isAndroid
                ? 'http://10.0.2.2:3000/api'
                : 'http://127.0.0.1:3000/api',
          );

    return AppConfig(
      environment: environment,
      apiBaseUrl: resolvedUrl,
      enableDevelopmentLogin:
          environment == AppEnvironment.development && enableDevelopmentLogin,
      enableAppleLogin: enableAppleLogin,
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

  static String _validatedProductionUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    final host = uri?.host.toLowerCase() ?? '';
    const forbiddenHosts = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};

    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        host.isEmpty ||
        forbiddenHosts.contains(host) ||
        host.endsWith('.localhost')) {
      throw ArgumentError.value(
        value,
        'productionApiBaseUrl',
        'Production API URL must use HTTPS and must not target a local host.',
      );
    }
    return normalized;
  }
}
