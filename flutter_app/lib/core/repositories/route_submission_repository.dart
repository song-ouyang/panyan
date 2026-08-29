import 'dart:io';

import '../models/route_submission_models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../json/json_helpers.dart';
import 'checkin_repository.dart';

typedef RouteCoverUploadProgress = void Function(double progress);

class RouteSubmissionRepository {
  const RouteSubmissionRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<String> uploadCover(
    String filePath, {
    RouteCoverUploadProgress? onProgress,
  }) => _apiClient.uploadFile(
    filePath,
    onSendProgress: onProgress == null
        ? null
        : (sent, total) {
            if (total > 0) onProgress((sent / total).clamp(0, 1));
          },
  );

  Future<RouteSubmission> create(RouteSubmissionDraft draft) async =>
      RouteSubmission.fromJson(
        await _apiClient.postJson('/submissions', data: draft.toJson()),
      );

  Future<String> uploadVideo(
    String filePath, {
    String? filename,
    String? mimeType,
    RouteCoverUploadProgress? onProgress,
  }) async {
    final mediaRepository = CheckinRepository(_apiClient);
    final size = await File(filePath).length();
    final originalName = filename?.trim().isNotEmpty == true
        ? filename!.trim()
        : File(filePath).uri.pathSegments.last;
    final lowerName = originalName.toLowerCase();
    final uploadName = lowerName.endsWith('.mp4') || lowerName.endsWith('.mov')
        ? originalName
        : '$originalName${mimeType == 'video/quicktime' ? '.mov' : '.mp4'}';
    Future<String> uploadDirect() => _apiClient.uploadFile(
      filePath,
      filename: uploadName,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress((sent / total).clamp(0, 1));
            },
    );
    if (size < 5 * 1024 * 1024) {
      return uploadDirect();
    }
    try {
      return await mediaRepository.uploadVideoMultipart(
        filePath,
        filename: filename,
        mimeType: mimeType,
        onProgress: onProgress,
      );
    } on ApiException catch (error) {
      if (!error.message.contains('OSS 分片上传尚未配置')) rethrow;
      return uploadDirect();
    }
  }

  Future<List<RouteSubmission>> mine() async {
    final json = await _apiClient.getJson('/submissions/mine');
    return jsonModelList(json['items'], RouteSubmission.fromJson);
  }
}
