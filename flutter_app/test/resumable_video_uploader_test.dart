import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/core/config/app_config.dart';
import 'package:wanpan_diary/core/json/json_helpers.dart';
import 'package:wanpan_diary/core/network/api_client.dart';
import 'package:wanpan_diary/core/network/api_exception.dart';
import 'package:wanpan_diary/core/services/resumable_video_uploader.dart';

const _config = AppConfig(
  environment: AppEnvironment.production,
  apiBaseUrl: 'https://api.example.com/api',
  enableDevelopmentLogin: false,
);

String _token(String user, [int revision = 1]) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'iat': revision})))}.signature';

class _MemoryCheckpoints implements MultipartCheckpointStore {
  final entries = <String, JsonMap>{};
  @override
  Future<JsonMap?> read(String key) async => entries[key];
  @override
  Future<void> write(String key, JsonMap value) async => entries[key] = value;
  @override
  Future<void> remove(String key) async => entries.remove(key);
}

class _UploadApi extends ApiClient {
  _UploadApi({AccessTokenProvider? tokenProvider})
    : super(
        config: _config,
        accessTokenProvider: tokenProvider ?? (() => _token('user-1')),
      );

  final parts = <int, List<int>>{};
  final puts = <int>[];
  final requests = <String>[];
  final signatures = <int, int>{};
  int activePuts = 0;
  int maxActivePuts = 0;
  int initCount = 0;
  int completeCount = 0;
  bool completed = false;
  bool loseCompletionResponse = false;
  bool expireNextSignature = false;
  int? failingPart;
  ApiException? statusError;
  List<int>? completionOrder;
  int size = 0;
  void Function()? onCompleteResponse;
  void Function()? onStatusResponse;

  @override
  Future<JsonMap> postJson(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(path);
    final body = jsonMap(data);
    switch (path) {
      case '/uploads/multipart/init':
        initCount++;
        completed = false;
        parts.clear();
        size = body['size'] as int;
        return {
          'key': 'videos/user-1/video-$initCount.mp4',
          'uploadId': 'id-$initCount',
          'partSize': 4,
          'size': size,
        };
      case '/uploads/multipart/status':
        if (statusError != null) throw statusError!;
        if (completed) {
          onStatusResponse?.call();
          return {
            'state': 'completed',
            'url': 'https://oss.example.com/video.mp4',
            'size': size,
          };
        }
        return {
          'state': 'uploading',
          'parts': [
            for (final part in parts.entries)
              {
                'number': part.key,
                'etag': 'etag-${part.key}',
                'size': part.value.length,
              },
          ],
        };
      case '/uploads/multipart/part-url':
        final number = body['partNumber'] as int;
        signatures[number] = (signatures[number] ?? 0) + 1;
        return {
          'url':
              'https://oss.example.com/part/$number?signature=${signatures[number]}',
        };
      case '/uploads/multipart/complete':
        completeCount++;
        completionOrder = (body['parts'] as List)
            .map((part) => part['number'] as int)
            .toList();
        expect(completionOrder, [
          for (var i = 1; i <= (size / 4).ceil(); i++) i,
        ]);
        completed = true;
        if (loseCompletionResponse) {
          throw const ApiException(message: 'response lost', statusCode: 503);
        }
        onCompleteResponse?.call();
        return {'url': 'https://oss.example.com/video.mp4'};
      default:
        throw StateError('Unexpected $path');
    }
  }

  @override
  Future<String> putBytesAndReadEtag(
    String url,
    List<int> bytes, {
    ProgressCallback? onSendProgress,
  }) async {
    final number = int.parse(Uri.parse(url).pathSegments.last);
    puts.add(number);
    activePuts++;
    maxActivePuts = max(maxActivePuts, activePuts);
    try {
      onSendProgress?.call(bytes.length ~/ 2, bytes.length);
      await Future<void>.delayed(Duration(milliseconds: number == 1 ? 15 : 3));
      if (number == failingPart) {
        throw const ApiException(message: 'connection lost');
      }
      if (expireNextSignature) {
        expireNextSignature = false;
        throw const ApiException(message: 'expired signature', statusCode: 403);
      }
      parts[number] = List.of(bytes);
      onSendProgress?.call(bytes.length, bytes.length);
      return 'etag-$number';
    } finally {
      activePuts--;
    }
  }
}

void main() {
  late Directory directory;
  late File file;
  late _MemoryCheckpoints store;
  late _UploadApi api;
  ResumableVideoUploader uploader() =>
      ResumableVideoUploader(api, checkpoints: store, delay: (_) async {});

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wanpan-resume-test-');
    file = await File('${directory.path}/original.mp4')
        .writeAsBytes(List.generate(19, (i) => i));
    store = _MemoryCheckpoints();
    api = _UploadApi();
  });
  tearDown(() async {
    api.dispose();
    await directory.delete(recursive: true);
  });

  test('three parallel workers preserve file bytes, sorted completion and monotonic progress', () async {
    final progress = <double>[];
    await uploader().upload(file.path, onProgress: progress.add);
    expect(api.maxActivePuts, 3);
    expect(api.parts.values.fold(0, (int sum, part) => sum + part.length), 19);
    expect([
      for (var i = 1; i <= 5; i++) ...api.parts[i]!,
    ], await file.readAsBytes());
    expect(progress.last, 1);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(progress.where((p) => p == 1), hasLength(1));
  });

  test('retry exhaustion retains task, new uploader and reselected file resume only missing parts', () async {
    api.failingPart = 2;
    await expectLater(
      uploader().upload(file.path),
      throwsA(isA<ApiException>()),
    );
    expect(api.puts.where((number) => number == 2), hasLength(4));
    expect(api.requests, isNot(contains('/uploads/multipart/abort')));
    expect(store.entries, hasLength(1));
    expect(api.activePuts, 0);
    final received = api.parts.keys.toSet();
    api.failingPart = null;
    api.puts.clear();
    final reselected = await file.copy('${directory.path}/reselected.mov');
    await uploader().upload(reselected.path);
    expect(api.initCount, 1);
    expect(api.puts.toSet().intersection(received), isEmpty);
    expect(api.puts, contains(2));
  });

  test('retry renews signed URL after OSS 403', () async {
    api.expireNextSignature = true;
    await uploader().upload(file.path);
    expect(api.signatures.values.any((count) => count == 2), isTrue);
    expect(api.initCount, 1);
  });

  test(
    'lost complete responses reconcile completed object without another upload',
    () async {
      api.loseCompletionResponse = true;
      await expectLater(
        uploader().upload(file.path),
        throwsA(isA<ApiException>()),
      );
      expect(api.completeCount, 4);
      api.puts.clear();
      api.loseCompletionResponse = false;
      expect(
        await uploader().upload(file.path),
        'https://oss.example.com/video.mp4',
      );
      expect(api.puts, isEmpty);
      expect(api.initCount, 1);
      expect(api.completeCount, 4);
    },
  );

  test(
    'status network error preserves task and never starts a replacement',
    () async {
      await uploader().upload(file.path);
      api.statusError = const ApiException(message: 'offline', statusCode: 503);
      await expectLater(
        uploader().upload(file.path),
        throwsA(isA<ApiException>()),
      );
      expect(api.initCount, 1);
      expect(store.entries, hasLength(1));
    },
  );

  test(
    'only explicit UPLOAD_NOT_FOUND resets task, old-server 404 does not',
    () async {
      await uploader().upload(file.path);
      api.statusError = const ApiException(
        message: 'not found',
        statusCode: 404,
      );
      await expectLater(
        uploader().upload(file.path),
        throwsA(isA<ApiException>()),
      );
      expect(api.initCount, 1);
      api.statusError = const ApiException(
        code: 'UPLOAD_NOT_FOUND',
        message: 'expired',
        statusCode: 404,
      );
      await uploader().upload(file.path);
      expect(api.initCount, 2);
    },
  );

  test('token refresh retains owner scope, switching accounts creates an isolated task', () async {
    var token = _token('user-1');
    api.dispose();
    api = _UploadApi(tokenProvider: () => token);
    await uploader().upload(file.path);
    token = _token('user-1', 2);
    await uploader().upload(file.path);
    expect(api.initCount, 1);
    token = _token('user-2');
    await uploader().upload(file.path);
    expect(api.initCount, 2);
    expect(store.entries, hasLength(2));
    expect(jsonEncode(store.entries), isNot(contains(token)));
  });

  for (final stage in ['complete', 'status']) {
    test(
      'account switch while waiting for $stage cannot return another owner video',
      () async {
        var token = _token('user-1');
        api.dispose();
        api = _UploadApi(tokenProvider: () => token);
        if (stage == 'status') {
          await uploader().upload(file.path);
          api.onStatusResponse = () => token = _token('user-2');
        } else {
          api.onCompleteResponse = () => token = _token('user-2');
        }
        await expectLater(
          uploader().upload(file.path),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'UPLOAD_SESSION_CHANGED',
            ),
          ),
        );
      },
    );
  }

  test('same name and size with different contents cannot reuse a completed upload', () async {
    await uploader().upload(file.path);
    await file.writeAsBytes(List.filled(19, 99));
    await uploader().upload(file.path);
    expect(api.initCount, 2);
  });

  test(
    'mismatched part length is replaced rather than counted as completed',
    () async {
      api.failingPart = 2;
      await expectLater(
        uploader().upload(file.path),
        throwsA(isA<ApiException>()),
      );
      api.parts[1] = [1];
      api.failingPart = null;
      api.puts.clear();
      await uploader().upload(file.path);
      expect(api.puts, contains(1));
      expect(api.parts[1], [0, 1, 2, 3]);
    },
  );
}
