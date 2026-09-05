import '../models/route_submission_models.dart';
import '../network/api_client.dart';
import '../json/json_helpers.dart';
import 'checkin_repository.dart';

typedef RouteCoverUploadProgress = void Function(double progress);

class RouteSubmissionRepository {
  const RouteSubmissionRepository(this._apiClient, {this.mediaRepository});

  final ApiClient _apiClient;
  final CheckinRepository? mediaRepository;

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

  Future<RouteSubmission> create(RouteSubmissionDraft draft) async {
    final result = RouteSubmission.fromJson(
      await _apiClient.postJson('/submissions', data: draft.toJson()),
    );
    _apiClient.climbingActivity.recordChanged();
    return result;
  }

  Future<String> uploadVideo(
    String filePath, {
    String? filename,
    String? mimeType,
    RouteCoverUploadProgress? onProgress,
    VideoUploadPhaseChanged? onPhaseChanged,
  }) => (mediaRepository ?? CheckinRepository(_apiClient)).uploadVideo(
    filePath,
    onProgress: onProgress,
    onPhaseChanged: onPhaseChanged,
  );

  Future<List<RouteSubmission>> mine() async {
    final json = await _apiClient.getJson('/submissions/mine');
    return jsonModelList(json['items'], RouteSubmission.fromJson);
  }
}
