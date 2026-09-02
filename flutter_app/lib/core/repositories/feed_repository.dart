import '../json/json_helpers.dart';
import '../models/feed_models.dart';
import '../network/api_client.dart';

class FeedRepository {
  const FeedRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<FeedPage> getFeed({
    DateTime? cursor,
    int limit = 20,
    String scope = 'square',
  }) async => FeedPage.fromJson(
    await _apiClient.getJson(
      '/sends/feed',
      queryParameters: {
        if (cursor != null) 'cursor': cursor.toUtc().toIso8601String(),
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

  Future<FeedComment> addComment(String postId, String content) async =>
      FeedComment.fromJson(
        await _apiClient.postJson(
          '/sends/$postId/comments',
          data: {'content': content},
        ),
      );

  Future<void> deleteComment(String postId, String commentId) async {
    await _apiClient.deleteJson('/sends/$postId/comments/$commentId');
  }

  Future<void> deletePost(String postId) async {
    await _apiClient.deleteJson('/sends/$postId');
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
