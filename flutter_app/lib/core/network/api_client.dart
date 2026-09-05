// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../json/json_helpers.dart';
import '../services/climbing_activity_changes.dart';
import 'api_exception.dart';

typedef AccessTokenProvider = FutureOr<String?> Function();
typedef UnauthorizedHandler = FutureOr<void> Function(
  String rejectedAccessToken,
);

class ApiClient {
  ApiClient({
    required AppConfig config,
    required AccessTokenProvider accessTokenProvider,
    Dio? dio,
  }) : _accessTokenProvider = accessTokenProvider,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.apiBaseUrl,
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 60),
               headers: const {'Accept': 'application/json'},
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_isFirstPartyRequest(options.uri)) {
            final token = await _accessTokenProvider();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401 &&
              _isFirstPartyRequest(error.requestOptions.uri)) {
            final rejectedAccessToken = _bearerToken(
              error.requestOptions.headers['Authorization'],
            );
            final callback = onUnauthorized;
            if (callback != null && rejectedAccessToken != null) {
              unawaited(Future<void>.sync(() => callback(rejectedAccessToken)));
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final climbingActivity = ClimbingActivityChanges();
  final AccessTokenProvider _accessTokenProvider;
  UnauthorizedHandler? onUnauthorized;

  void dispose() {
    climbingActivity.dispose();
    _dio.close();
  }

  Future<JsonMap> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) => _requestJson('GET', path, queryParameters: queryParameters);

  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) =>
      _requestJson('POST', path, data: data, queryParameters: queryParameters);

  Future<JsonMap> patchJson(String path, {Object? data}) =>
      _requestJson('PATCH', path, data: data);

  Future<JsonMap> deleteJson(String path, {Object? data}) =>
      _requestJson('DELETE', path, data: data);

  Future<String> uploadFile(
    String filePath, {
    String fieldName = 'file',
    String? filename,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final uploadName = filename ?? filePath.split('/').last;
      final data = FormData.fromMap({
        fieldName: await MultipartFile.fromFile(
          filePath,
          filename: uploadName,
          contentType: _mediaType(uploadName),
        ),
      });
      final response = await _dio.post<Object?>(
        '/uploads',
        data: data,
        onSendProgress: onSendProgress,
      );
      return jsonString(jsonMap(response.data)['url'], field: 'url');
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  DioMediaType _mediaType(String filename) {
    final extension = filename.toLowerCase().split('.').last;
    return switch (extension) {
      'jpg' || 'jpeg' => DioMediaType('image', 'jpeg'),
      'png' => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      'mp4' => DioMediaType('video', 'mp4'),
      'mov' => DioMediaType('video', 'quicktime'),
      _ => DioMediaType('application', 'octet-stream'),
    };
  }

  Future<String> putBytesAndReadEtag(String url, List<int> bytes) async {
    try {
      final response = await _dio.put<Object?>(
        url,
        data: Stream<List<int>>.value(bytes),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {'Content-Length': bytes.length},
        ),
      );
      final etag = response.headers.value('etag');
      if (etag == null || etag.isEmpty) {
        throw const ApiException(
          code: 'MISSING_ETAG',
          message: 'OSS did not return an ETag header',
        );
      }
      return etag;
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  Future<JsonMap> _requestJson(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method),
      );
      return jsonMap(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  bool _isFirstPartyRequest(Uri uri) {
    final base = Uri.parse(_dio.options.baseUrl);
    return uri.host == base.host && uri.port == base.port;
  }

  String? _bearerToken(Object? authorization) {
    if (authorization is! String) return null;
    const prefix = 'Bearer ';
    if (!authorization.startsWith(prefix)) return null;
    final token = authorization.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  ApiException _toApiException(DioException error) {
    final response = error.response;
    JsonMap? body;
    try {
      body = jsonMap(response?.data);
    } on FormatException {
      body = null;
    }
    return ApiException(
      statusCode: response?.statusCode,
      code: jsonNullableString(body?['code']) ?? 'REQUEST_FAILED',
      message:
          jsonNullableString(body?['message']) ??
          (error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.receiveTimeout
              ? '请求超时，请稍后重试'
              : '网络请求失败'),
      issues: body?['issues'] is List
          ? List<dynamic>.from(body!['issues'] as List)
          : const [],
      cause: error,
    );
  }
}
