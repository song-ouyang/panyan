import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../json/json_helpers.dart';
import '../models/checkin_models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

abstract interface class MultipartCheckpointStore {
  Future<JsonMap?> read(String key);
  Future<void> write(String key, JsonMap value);
  Future<void> remove(String key);
}

/// Only the upload ID and object key are persisted, never tokens or signed URLs.
/// OSS is authoritative for successfully received parts, including PUTs whose
/// responses were lost or whose client process was killed before a local save.
class PreferencesMultipartCheckpointStore implements MultipartCheckpointStore {
  static const _prefix = 'wanpan.video.multipart.v1.';
  final _preferences = SharedPreferencesAsync();

  @override
  Future<JsonMap?> read(String key) async {
    final raw = await _preferences.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonMap(jsonDecode(raw));
    } on FormatException {
      await remove(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, JsonMap value) =>
      _preferences.setString('$_prefix$key', jsonEncode(value));

  @override
  Future<void> remove(String key) => _preferences.remove('$_prefix$key');
}

typedef UploadDelay = Future<void> Function(Duration duration);

class ResumableVideoUploader {
  ResumableVideoUploader(
    this.api, {
    this.checkpoints,
    UploadDelay? delay,
    this.concurrency = 3,
  }) : assert(concurrency >= 1 && concurrency <= 3),
       _delay = delay ?? Future<void>.delayed;

  final ApiClient api;
  final int concurrency;
  final MultipartCheckpointStore? checkpoints;
  final UploadDelay _delay;
  static final _active = <String, Future<String>>{};

  Future<String> upload(
    String path, {
    String? filename,
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    final scope = await api.videoUploadScope();
    final file = File(path);
    final before = await file.stat();
    if (before.size <= 0) {
      throw const ApiException(code: 'EMPTY_VIDEO', message: '视频文件为空，请重新选择');
    }
    final digest = await sha256.bind(file.openRead()).first;
    final after = await file.stat();
    _assertUnchanged(before, after);
    final checkpointKey = '$scope.$digest';
    final running = _active[checkpointKey];
    if (running != null) {
      final url = await running;
      await _assertScope(scope);
      onProgress?.call(1);
      return url;
    }
    final future = _upload(
      file,
      before,
      scope,
      checkpointKey,
      filename ?? file.uri.pathSegments.last,
      mimeType ??
          (path.toLowerCase().endsWith('.mov')
              ? 'video/quicktime'
              : 'video/mp4'),
      onProgress,
    );
    _active[checkpointKey] = future;
    try {
      final url = await future;
      await _assertScope(scope);
      return url;
    } finally {
      _active.remove(checkpointKey);
    }
  }

  Future<String> _upload(
    File file,
    FileStat original,
    String scope,
    String checkpointKey,
    String filename,
    String mimeType,
    void Function(double)? onProgress,
  ) async {
    final store = checkpoints ?? PreferencesMultipartCheckpointStore();
    final saved = await store.read(checkpointKey);
    MultipartUploadTask? task;
    if (saved != null) {
      try {
        task = MultipartUploadTask.fromJson(saved);
        _validateTask(task, original.size);
      } on FormatException {
        await store.remove(checkpointKey);
        task = null;
      }
    }
    final completed = <int, UploadedPart>{};
    if (task != null) {
      try {
        final status = await _retry(() async {
          await _assertScope(scope);
          return api.postJson(
            '/uploads/multipart/status',
            data: {'key': task!.key, 'uploadId': task.uploadId},
          );
        });
        if (status['state'] == 'completed') {
          if (jsonInt(status['size']) != original.size) {
            throw const FormatException('Uploaded video size does not match');
          }
          onProgress?.call(1);
          return jsonString(status['url'], field: 'url');
        }
        if (status['state'] != 'uploading') {
          throw const FormatException('Invalid multipart status');
        }
        final total = (original.size / task.partSize).ceil();
        for (final value in jsonList(status['parts'])) {
          final part = jsonMap(value);
          final number = jsonInt(part['number']);
          if (number < 1 || number > total) continue;
          final expected = min(
            task.partSize,
            original.size - (number - 1) * task.partSize,
          );
          final etag = jsonString(part['etag'], field: 'etag');
          if (jsonInt(part['size']) == expected && etag.isNotEmpty) {
            completed[number] = UploadedPart(number: number, etag: etag);
          }
        }
      } on ApiException catch (error) {
        if (error.statusCode != 404 || error.code != 'UPLOAD_NOT_FOUND') {
          rethrow;
        }
        await store.remove(checkpointKey);
        task = null;
      }
    }
    if (task == null) {
      task = MultipartUploadTask.fromJson(
        await _retry(() async {
          await _assertScope(scope);
          return api.postJson(
            '/uploads/multipart/init',
            data: {
              'filename': filename,
              'mimeType': mimeType,
              'size': original.size,
            },
          );
        }),
      );
      _validateTask(task, original.size);
      // Commit the task before sending any file bytes so a process restart can
      // reconcile every successful part directly with OSS.
      await store.write(checkpointKey, {
        'key': task.key,
        'uploadId': task.uploadId,
        'partSize': task.partSize,
        'size': task.size,
      });
    }
    final upload = task;
    final total = (original.size / upload.partSize).ceil();
    final pending = [
      for (var i = 1; i <= total; i++)
        if (!completed.containsKey(i)) i,
    ];
    final inFlight = <int, int>{};
    var next = 0;
    var stopped = false;
    var highWater = 0.0;
    int partLength(int number) =>
        min(upload.partSize, original.size - (number - 1) * upload.partSize);
    void report() {
      final received = completed.keys.fold<int>(
        0,
        (sum, number) => sum + partLength(number),
      );
      final sending = inFlight.values.fold<int>(0, (sum, bytes) => sum + bytes);
      // Retries cannot move the progress bar backward. Completion remains a
      // distinct phase, even when the socket has sent all bytes.
      highWater = max(
        highWater,
        min(.99, (received + sending) / original.size),
      );
      onProgress?.call(highWater);
    }

    report();
    Future<void> worker() async {
      while (!stopped && next < pending.length) {
        final number = pending[next++];
        final start = (number - 1) * upload.partSize;
        final length = partLength(number);
        try {
          final builder = await file
              .openRead(start, start + length)
              .fold<BytesBuilder>(
                BytesBuilder(copy: false),
                (buffer, data) => buffer..add(data),
              );
          final bytes = builder.takeBytes();
          if (bytes.length != length) {
            throw const ApiException(
              code: 'VIDEO_CHANGED',
              message: '视频文件已变化，请重新选择',
            );
          }
          final etag = await _retry(() async {
            await _assertScope(scope);
            inFlight[number] = 0;
            final signed = await api.postJson(
              '/uploads/multipart/part-url',
              data: {
                'key': upload.key,
                'uploadId': upload.uploadId,
                'partNumber': number,
              },
            );
            await _assertScope(scope);
            return api.putBytesAndReadEtag(
              jsonString(signed['url'], field: 'url'),
              bytes,
              onSendProgress: (sent, _) {
                inFlight[number] = sent.clamp(0, length);
                report();
              },
            );
          }, retryExpiredSignature: true);
          inFlight.remove(number);
          completed[number] = UploadedPart(number: number, etag: etag);
          report();
        } catch (_) {
          stopped = true;
          rethrow;
        }
      }
    }

    // Wait for all in-flight workers even after one fails, so none can still
    // mutate progress after the caller has returned or started a retry.
    await Future.wait(
      List.generate(min(concurrency, pending.length), (_) => worker()),
    );
    _assertUnchanged(original, await file.stat());
    final parts = completed.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    final result = await _retry(() async {
      await _assertScope(scope);
      return api.postJson(
        '/uploads/multipart/complete',
        data: {
          'key': upload.key,
          'uploadId': upload.uploadId,
          'parts': parts.map((part) => part.toJson()).toList(growable: false),
        },
      );
    });
    // Keep the task for re-publication after a save/network failure. A future
    // retry asks status, so it never blindly trusts a stale cached object URL.
    onProgress?.call(1);
    return jsonString(result['url'], field: 'url');
  }

  Future<T> _retry<T>(
    Future<T> Function() action, {
    bool retryExpiredSignature = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await action();
      } on ApiException catch (error) {
        final status = error.statusCode;
        final retryable =
            error.code != 'OSS_NOT_CONFIGURED' &&
            error.code != 'UPLOAD_SESSION_CHANGED' &&
            (status == null ||
                status == 408 ||
                status == 429 ||
                status >= 500 ||
                (retryExpiredSignature && status == 403));
        if (!retryable || attempt >= 3) rethrow;
        var pause = Duration(
          milliseconds: (1 << attempt) * 700 + Random().nextInt(250),
        );
        final retryAt = error.retryAt;
        if (retryAt != null) {
          final remaining = retryAt.difference(DateTime.now());
          if (remaining > const Duration(seconds: 30)) rethrow;
          if (remaining > pause) pause = remaining;
        }
        await _delay(pause);
      }
    }
  }

  Future<void> _assertScope(String expected) async {
    if (await api.videoUploadScope() != expected) {
      throw const ApiException(
        code: 'UPLOAD_SESSION_CHANGED',
        message: '登录账号已切换，请重新提交视频',
      );
    }
  }

  static void _validateTask(MultipartUploadTask task, int size) {
    if (task.size != size ||
        task.partSize <= 0 ||
        task.partSize > 20 * 1024 * 1024 ||
        task.key.isEmpty ||
        task.uploadId.isEmpty ||
        (size / task.partSize).ceil() > 10000) {
      throw const FormatException('Invalid multipart upload task');
    }
  }

  static void _assertUnchanged(FileStat before, FileStat after) {
    if (before.size != after.size || before.modified != after.modified) {
      throw const ApiException(code: 'VIDEO_CHANGED', message: '视频文件已变化，请重新选择');
    }
  }
}
