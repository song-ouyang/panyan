import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'https://api.example.com/api',
  enableDevelopmentLogin: false,
);

class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"code":"UNAUTHORIZED","message":"expired"}',
    401,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  test('401 callback receives the bearer token used by that request', () async {
    final dio = Dio(BaseOptions(baseUrl: _config.apiBaseUrl));
    dio.httpClientAdapter = _UnauthorizedAdapter();
    final api = ApiClient(
      config: _config,
      accessTokenProvider: () => 'request-token',
      dio: dio,
    );
    String? rejectedToken;
    api.onUnauthorized = (token) => rejectedToken = token;

    await expectLater(api.getJson('/protected'), throwsA(isA<ApiException>()));

    expect(rejectedToken, 'request-token');
  });

  test(
    'an unauthenticated 401 cannot invalidate a concurrent session',
    () async {
      final dio = Dio(BaseOptions(baseUrl: _config.apiBaseUrl));
      dio.httpClientAdapter = _UnauthorizedAdapter();
      final api = ApiClient(
        config: _config,
        accessTokenProvider: () => null,
        dio: dio,
      );
      var callbackCount = 0;
      api.onUnauthorized = (_) => callbackCount++;

      await expectLater(api.getJson('/public'), throwsA(isA<ApiException>()));

      expect(callbackCount, 0);
    },
  );
}
