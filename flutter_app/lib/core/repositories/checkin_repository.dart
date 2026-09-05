import 'dart:io';

import '../json/json_helpers.dart';
import '../models/checkin_models.dart';
import '../network/api_client.dart';

typedef UploadProgress = void Function(double progress);

class CheckinRepository {
  const CheckinRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<String> uploadMedia(String filePath, {UploadProgress? onProgress}) =>
      _apiClient.uploadFile(
        filePath,
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress((sent / total).clamp(0, 1));
              },
      );

  Future<String> uploadVideoMultipart(
    String filePath, {
    String? filename,
    String? mimeType,
    UploadProgress? onProgress,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    final uploadName = filename?.trim().isNotEmpty == true
        ? filename!.trim()
        : file.uri.pathSegments.last;
    final uploadMimeType =
        mimeType ??
        (uploadName.toLowerCase().endsWith('.mov')
            ? 'video/quicktime'
            : 'video/mp4');
    final task = MultipartUploadTask.fromJson(
      await _apiClient.postJson(
        '/uploads/multipart/init',
        data: {
          'filename': uploadName,
          'mimeType': uploadMimeType,
          'size': size,
        },
      ),
    );
    final parts = <UploadedPart>[];
    RandomAccessFile? reader;
    try {
      reader = await file.open();
      var uploaded = 0;
      var partNumber = 1;
      while (uploaded < size) {
        final length = (size - uploaded).clamp(0, task.partSize);
        final bytes = await reader.read(length);
        final signed = await _apiClient.postJson(
          '/uploads/multipart/part-url',
          data: {
            'key': task.key,
            'uploadId': task.uploadId,
            'partNumber': partNumber,
          },
        );
        final etag = await _apiClient.putBytesAndReadEtag(
          jsonString(signed['url'], field: 'url'),
          bytes,
        );
        parts.add(UploadedPart(number: partNumber, etag: etag));
        uploaded += bytes.length;
        partNumber += 1;
        onProgress?.call((uploaded / size).clamp(0, 1));
      }
      final completed = await _apiClient.postJson(
        '/uploads/multipart/complete',
        data: {
          'key': task.key,
          'uploadId': task.uploadId,
          'parts': parts.map((part) => part.toJson()).toList(growable: false),
        },
      );
      return jsonString(completed['url'], field: 'url');
    } catch (_) {
      try {
        await _apiClient.postJson(
          '/uploads/multipart/abort',
          data: {'key': task.key, 'uploadId': task.uploadId},
        );
      } catch (_) {
        // Preserve the upload error; abort is best-effort cleanup.
      }
      rethrow;
    } finally {
      await reader?.close();
    }
  }

  Future<CheckinResult> createCheckin({
    required String routeId,
    int attempts = 1,
    String? videoUrl,
    String? caption,
    String visibility = 'public',
  }) async {
    final result = CheckinResult.fromJson(
      await _apiClient.postJson(
        '/sends',
        data: {
          'routeId': routeId,
          'attempts': attempts,
          'videoUrl': videoUrl,
          'caption': caption,
          'visibility': visibility,
        },
      ),
    );
    _apiClient.climbingActivity.recordChanged();
    return result;
  }
}
