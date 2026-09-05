import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';

class _LimitedAdapter implements HttpClientAdapter {
  _LimitedAdapter(this.headers);

  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"message":"Too many requests"}',
    429,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<ApiException> _request(Map<String, List<String>> headers) async {
  const config = AppConfig(
    environment: AppEnvironment.development,
    apiBaseUrl: 'https://api.example.com/api',
    enableDevelopmentLogin: false,
  );
  final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl))
    ..httpClientAdapter = _LimitedAdapter(headers);
  final api = ApiClient(
    config: config,
    accessTokenProvider: () => null,
    dio: dio,
  );
  addTearDown(api.dispose);
  try {
    await api.postJson('/auth/sms/login');
    fail('Expected a rate limit error');
  } on ApiException catch (error) {
    return error;
  }
}

void main() {
  test('Retry-After 秒数保留为截止时间', () async {
    final before = DateTime.now();
    final error = await _request({
      'retry-after': ['415'],
    });
    expect(error.statusCode, 429);
    expect(error.retryAt, isNotNull);
    expect(
      error.retryAt!.isBefore(before.add(const Duration(seconds: 415))),
      isFalse,
    );
    expect(
      error.retryAt!.isAfter(DateTime.now().add(const Duration(seconds: 415))),
      isFalse,
    );
  });

  test('HTTP 日期依据服务器 Date 校正客户端时差', () async {
    final serverNow = DateTime.utc(2020, 1, 1);
    final before = DateTime.now();
    final error = await _request({
      'date': [HttpDate.format(serverNow)],
      'retry-after': [
        HttpDate.format(serverNow.add(const Duration(seconds: 90))),
      ],
    });
    expect(
      error.retryAt!.isBefore(before.add(const Duration(seconds: 90))),
      isFalse,
    );
    expect(
      error.retryAt!.isAfter(DateTime.now().add(const Duration(seconds: 90))),
      isFalse,
    );
  });

  test('无效 Date 不影响有效的 Retry-After 日期', () async {
    final deadline = DateTime.now().toUtc().add(const Duration(minutes: 3));
    final value = HttpDate.format(deadline);
    final error = await _request({
      'date': ['invalid-date'],
      'retry-after': [value],
    });
    expect(error.retryAt, HttpDate.parse(value));
  });

  for (final value in [null, '', '-1', 'invalid-date', '1.5']) {
    test('缺少或无效等待时间仍返回原始429: $value', () async {
      final error = await _request({
        if (value != null) 'retry-after': [value],
      });
      expect(error.statusCode, 429);
      expect(error.message, 'Too many requests');
      expect(error.retryAt, isNull);
    });
  }

  test('过期 Retry-After 日期立即可重试', () async {
    final before = DateTime.now();
    final error = await _request({
      'retry-after': [
        HttpDate.format(before.subtract(const Duration(seconds: 5))),
      ],
    });
    expect(error.retryAt!.isBefore(before), isFalse);
    expect(error.retryAt!.isAfter(DateTime.now()), isFalse);
  });
}
