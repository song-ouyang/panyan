import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/repositories/share_repository.dart';

const _token = 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE';

void main() {
  test(
    'share links use the website origin and escape individual route IDs',
    () {
      final api = _ShareApi();
      final repository = ShareRepository(api);
      expect(
        repository.routeUrl('route/one?').toString(),
        'https://share.example.com/share/route/route%2Fone%3F',
      );
      expect(
        repository.monthlyUrl(_token).toString(),
        'https://share.example.com/share/monthly/$_token',
      );
      expect(api.calls, isEmpty);
    },
  );

  test('lookup is read-only; create and revoke use owner API paths', () async {
    final api = _ShareApi();
    final repository = ShareRepository(api);
    api.response = {'month': '2026-08', 'token': null};
    expect(await repository.getMonthlyToken('2026-08'), isNull);
    expect(api.calls.single.$1, 'GET');
    expect(api.calls.single.$2, '/shares/monthly');
    expect(api.calls.single.$3, {'month': '2026-08'});
    api.response = {'month': '2026-08', 'token': _token};
    expect(await repository.createMonthlyShare('2026-08'), _token);
    expect(api.calls.last.$1, 'POST');
    expect(api.calls.last.$2, '/shares/monthly');
    expect(api.calls.last.$3, {'month': '2026-08'});
    await repository.revokeMonthlyShare(_token);
    expect(api.calls.last, ('DELETE', '/shares/monthly/$_token', null));
  });

  test(
    'rejects malformed or mismatched responses before constructing a URL',
    () async {
      final api = _ShareApi();
      final repository = ShareRepository(api);
      for (final response in [
        {'month': '2026-07', 'token': _token},
        {'month': '2026-08', 'token': 'bad/token'},
        {'month': '2026-08', 'token': 42},
      ]) {
        api.response = response;
        await expectLater(
          repository.getMonthlyToken('2026-08'),
          throwsFormatException,
        );
      }
      api.response = {'month': '2026-08', 'token': null};
      await expectLater(
        repository.createMonthlyShare('2026-08'),
        throwsFormatException,
      );
    },
  );

  test('invalid months and tokens never reach the API', () async {
    final api = _ShareApi();
    final repository = ShareRepository(api);
    for (final month in ['2026-13', '2026-00', '2026-8', '../../x']) {
      await expectLater(
        repository.createMonthlyShare(month),
        throwsFormatException,
      );
    }
    await expectLater(
      repository.revokeMonthlyShare('../x'),
      throwsFormatException,
    );
    expect(api.calls, isEmpty);
  });

  test(
    'SHARE_BASE_URL is normalized and restricted to a production HTTPS origin',
    () {
      expect(
        AppConfig.validateShareBaseUrl(' https://share.example.com/ '),
        'https://share.example.com',
      );
      for (final url in [
        'http://example.com',
        'https://localhost',
        'https://example.com/api',
        'https://example.com?x=1',
        'https://example.com#x',
        'https://user:password@example.com',
      ]) {
        expect(() => AppConfig.validateShareBaseUrl(url), throwsArgumentError);
      }
      expect(
        AppConfig.fromEnvironment().shareBaseUrl,
        AppConfig.defaultShareBaseUrl,
      );
      final config = AppConfig.resolveForBuild(
        isReleaseMode: true,
        isAndroid: false,
        appEnvironment: 'production',
        apiBaseUrl: '',
        productionApiBaseUrl: AppConfig.productionApiBaseUrl,
        enableDevelopmentLogin: false,
        shareBaseUrl: 'https://share.example.com/',
      );
      expect(config.shareBaseUrl, 'https://share.example.com');
    },
  );
}

class _ShareApi extends ApiClient {
  _ShareApi()
    : super(
        config: const AppConfig(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://api.example.com/api',
          enableDevelopmentLogin: false,
          shareBaseUrl: 'https://share.example.com',
        ),
        accessTokenProvider: () => 'token',
      );

  JsonMap response = {};
  final calls = <(String, String, Object?)>[];

  @override
  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(('GET', path, queryParameters));
    return response;
  }

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(('POST', path, data));
    return response;
  }

  @override
  Future<JsonMap> deleteJson(String path, {Object? data}) async {
    calls.add(('DELETE', path, data));
    return {};
  }
}
