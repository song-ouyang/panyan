import '../config/app_config.dart';
import '../models/checkin_models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../services/resumable_video_uploader.dart';
import '../services/video_preparation_service.dart';

typedef UploadProgress = void Function(double progress);

enum VideoUploadPhase { preparing, uploading }

typedef VideoUploadPhaseChanged = void Function(VideoUploadPhase phase);

class CheckinRepository {
  const CheckinRepository(
    this._apiClient, {
    this.videoPreparation,
    this.videoUploader,
  });

  final ApiClient _apiClient;
  final VideoPreparationService? videoPreparation;
  final ResumableVideoUploader? videoUploader;

  Future<String> uploadMedia(String filePath, {UploadProgress? onProgress}) =>
      _apiClient.uploadFile(
        filePath,
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress((sent / total).clamp(0, 1));
              },
      );

  /// Both publication entry points use the same prepare -> OSS pipeline,
  /// including videos smaller than one part. Production never falls back to
  /// proxying the original video through the API server after a network error.
  Future<String> uploadVideo(
    String filePath, {
    UploadProgress? onProgress,
    VideoUploadPhaseChanged? onPhaseChanged,
  }) async {
    final scope = await _apiClient.videoUploadScope();
    onPhaseChanged?.call(VideoUploadPhase.preparing);
    onProgress?.call(0);
    final preparation = videoPreparation ?? VideoPreparationService();
    final video = await preparation.prepare(filePath, onProgress: onProgress);
    try {
      if (await _apiClient.videoUploadScope() != scope) {
        throw const ApiException(
          code: 'UPLOAD_SESSION_CHANGED',
          message: '登录账号已切换，请重新提交视频',
        );
      }
      onPhaseChanged?.call(VideoUploadPhase.uploading);
      onProgress?.call(0);
      try {
        final url = await uploadVideoMultipart(
          video.path,
          filename: video.filename,
          mimeType: video.mimeType,
          onProgress: onProgress,
        );
        await _assertUploadScope(scope);
        return url;
      } on ApiException catch (error) {
        final localDevelopment =
            _apiClient.config.environment == AppEnvironment.development;
        if (!localDevelopment || error.code != 'OSS_NOT_CONFIGURED') rethrow;
        final url = await _apiClient.uploadFile(
          video.path,
          filename: video.filename,
          onSendProgress: onProgress == null
              ? null
              : (sent, total) {
                  if (total > 0) onProgress((sent / total).clamp(0, 1));
                },
        );
        await _assertUploadScope(scope);
        return url;
      }
    } finally {
      preparation.release(video);
    }
  }

  Future<void> _assertUploadScope(String scope) async {
    if (await _apiClient.videoUploadScope() != scope) {
      throw const ApiException(
        code: 'UPLOAD_SESSION_CHANGED',
        message: '登录账号已切换，请重新提交视频',
      );
    }
  }

  Future<String> uploadVideoMultipart(
    String filePath, {
    String? filename,
    String? mimeType,
    UploadProgress? onProgress,
  }) => (videoUploader ?? ResumableVideoUploader(_apiClient)).upload(
    filePath,
    filename: filename,
    mimeType: mimeType,
    onProgress: onProgress,
  );

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
