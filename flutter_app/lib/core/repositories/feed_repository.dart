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
  }) async {
    final post = FeedPost.fromJson(
      await _apiClient.postJson(
        '/sends/moments',
        data: {
          'caption': caption,
          'imageUrls': imageUrls,
          'visibility': visibility,
        },
      ),
    );
    _apiClient.socialActivity.recordChanged(postId: post.id);
    return post;
  }

  Future<bool> setLiked(String postId, {required bool liked}) async {
    final json = liked
        ? await _apiClient.postJson('/sends/$postId/like')
        : await _apiClient.deleteJson('/sends/$postId/like');
    if (json['liked'] != liked) {
      throw const ApiException(message: '点赞没有保存，请重试');
    }
    _apiClient.socialActivity.recordChanged(postId: postId);
    return liked;
  }

  Future<bool> setFavorited(String postId, {required bool favorited}) async {
    final json = favorited
        ? await _apiClient.postJson('/sends/$postId/favorite')
        : await _apiClient.deleteJson('/sends/$postId/favorite');
    if (json['favorited'] != favorited) {
      throw const ApiException(message: '收藏没有保存，请重试');
    }
    _apiClient.socialActivity.recordChanged(postId: postId);
    return favorited;
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
    final comment = FeedComment.fromJson({
      if (author != null && json['user_id'] == author.id) ...{
        'nickname': author.nickname,
        'avatar_url': author.avatarUrl,
      },
      ...json,
    });
    _apiClient.socialActivity.recordChanged(postId: postId);
    return comment;
  }

  Future<void> deleteComment(String postId, String commentId) async {
    final result = await _apiClient.deleteJson(
      '/sends/$postId/comments/$commentId',
    );
    if (result['deleted'] != true) {
      throw const ApiException(message: '评论未删除，请稍后重试');
    }
    _apiClient.socialActivity.recordChanged(postId: postId);
  }

  Future<void> deletePost(String postId) async {
    final result = await _apiClient.deleteJson('/sends/$postId');
    if (result['deleted'] != true) {
      throw const ApiException(message: '动态未删除，请稍后重试');
    }
    _apiClient.climbingActivity.recordChanged();
    _apiClient.socialActivity.recordChanged(postId: postId, deleted: true);
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
    _apiClient.socialActivity.recordChanged();
  }
}
