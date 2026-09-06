import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';

import 'growth_repository_test.dart' as fixture;

void main() {
  for (final endpoint in [
    '/sends',
    '/submissions',
    '/users/me/growth-presentations/consume',
  ]) {
    test(
      '$endpoint cannot inherit a new account token in delayed Dio interceptor',
      () async {
        var token = 'account-a';
        final entered = Completer<void>();
        final release = Completer<void>();
        final dio = Dio(BaseOptions(baseUrl: fixture.config.apiBaseUrl));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              entered.complete();
              await release.future;
              handler.next(options);
            },
          ),
        );
        final api = ApiClient(
          config: fixture.config,
          accessTokenProvider: () => token,
          dio: dio,
        );
        addTearDown(api.dispose);
        final outgoing = <String>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              outgoing.add(options.headers['Authorization'] as String);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{},
                ),
              );
            },
          ),
        );
        final request = api.inSession(
          'account-a',
          () => api.postJson(endpoint, data: {'clientRequestId': 'draft-a'}),
        );
        final rejected = expectLater(
          request,
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'REQUEST_SESSION_CHANGED',
            ),
          ),
        );
        await entered.future;
        token = 'account-b';
        release.complete();
        await rejected;
        expect(outgoing, isEmpty);
      },
    );
  }
  test(
    'bound request keeps original Authorization after token-provider read',
    () async {
      var token = 'account-a';
      final dio = Dio(BaseOptions(baseUrl: fixture.config.apiBaseUrl));
      final api = ApiClient(
        config: fixture.config,
        accessTokenProvider: () {
          final current = token;
          token = 'account-b';
          return current;
        },
        dio: dio,
      );
      addTearDown(api.dispose);
      String? outgoing;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            outgoing = options.headers['Authorization'] as String;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );
      await api.inSession(
        'account-a',
        () => api.postJson('/sends', data: {'clientRequestId': 'draft-a'}),
      );
      expect(outgoing, 'Bearer account-a');
    },
  );
}
