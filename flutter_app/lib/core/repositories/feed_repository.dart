import '../json/json_helpers.dart';
import '../models/feed_models.dart';
import '../models/user_models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class FeedRepository {
  const FeedRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String scope = 'square',
  }) async => FeedPage.fromJson(
    await _apiClient.getJson(
      '/sends/feed',
      queryParameters: {
        'cursor': ?cursor,
        'limit': limit.clamp(1, 50),
        'scope': scope,
      },
    ),
  );

  Future<FeedPost> getPost(String postId) async =>
      FeedPost.fromJson(await _apiClient.getJson('/sends/$postId'));

  Future<FeedPost> publishMoment({
    String caption = '',
    List<String> imageUrls = const [],
    String visibility = 'public',
  }) async => FeedPost.fromJson(
    await _apiClient.postJson(
      '/sends/moments',
      data: {
        'caption': caption,
        'imageUrls': imageUrls,
        'visibility': visibility,
      },
    ),
  );

  Future<bool> setLiked(String postId, {required bool liked}) async {
    final json = liked
        ? await _apiClient.postJson('/sends/$postId/like')
        : await _apiClient.deleteJson('/sends/$postId/like');
    return jsonBool(json['liked']);
  }

  Future<FeedComment> addComment(
    String postId,
    String content, {
    UserSummary? author,
  }) async {
    final json = await _apiClient.postJson(
      '/sends/$postId/comments',
      data: {'content': content},
    );
    // Older servers return the saved comment without joined profile fields.
    // Only use the submitting account's profile for its own returned record.
    return FeedComment.fromJson({
      if (author != null && json['user_id'] == author.id) ...{
        'nickname': author.nickname,
        'avatar_url': author.avatarUrl,
      },
      ...json,
    });
  }

  Future<void> deleteComment(String postId, String commentId) async {
    await _apiClient.deleteJson('/sends/$postId/comments/$commentId');
  }

  Future<void> deletePost(String postId) async {
    final result = await _apiClient.deleteJson('/sends/$postId');
    if (result['deleted'] != true) {
      throw const ApiException(message: '动态未删除，请稍后重试');
    }
    _apiClient.climbingActivity.recordChanged();
    _apiClient.socialActivity.recordChanged();
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await _apiClient.postJson(
      '/reports',
      data: {'targetType': targetType, 'targetId': targetId, 'reason': reason},
    );
  }

  Future<void> blockUser(String userId) async {
    await _apiClient.postJson('/users/$userId/block');
  }
}
