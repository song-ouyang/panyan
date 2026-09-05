import '../json/json_helpers.dart';
import '../models/feed_models.dart';
import '../models/profile_models.dart';
import '../models/user_models.dart';
import '../network/api_client.dart';

class ProfileRepository {
  const ProfileRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<UserProfile> getMe() async =>
      UserProfile.fromJson(await _apiClient.getJson('/users/me'));

  Future<UserSummary> updateMe({
    required String nickname,
    String? avatarUrl,
    String? bio,
  }) async => UserSummary.fromJson(
    await _apiClient.patchJson(
      '/users/me',
      data: {'nickname': nickname, 'avatarUrl': avatarUrl, 'bio': bio},
    ),
  );

  Future<List<GrowthPoint>> getGrowth({int months = 6}) async {
    final json = await _apiClient.getJson(
      '/users/me/growth',
      queryParameters: {'months': months.clamp(1, 24)},
    );
    return jsonModelList(json['items'], GrowthPoint.fromJson);
  }

  Future<MonthDashboard> getMonthDashboard(String month) async =>
      MonthDashboard.fromJson(
        await _apiClient.getJson(
          '/users/me/month-dashboard',
          queryParameters: {'month': month},
        ),
      );

  Future<List<MyPost>> getMyPosts() async {
    final json = await _apiClient.getJson('/users/me/sends');
    return jsonModelList(json['items'], MyPost.fromJson);
  }

  Future<MyCommentPage> getMyComments({String? cursor, int limit = 20}) async =>
      MyCommentPage.fromJson(
        await _apiClient.getJson(
          '/users/me/comments',
          queryParameters: {'cursor': ?cursor, 'limit': limit.clamp(1, 50)},
        ),
      );

  Future<FeedPage> getMyFavorites({String? cursor, int limit = 20}) async =>
      FeedPage.fromJson(
        await _apiClient.getJson(
          '/users/me/favorites',
          queryParameters: {'cursor': ?cursor, 'limit': limit.clamp(1, 50)},
        ),
      );

  Future<FeedPage> getMyLikes({String? cursor, int limit = 20}) async =>
      FeedPage.fromJson(
        await _apiClient.getJson(
          '/users/me/likes',
          queryParameters: {'cursor': ?cursor, 'limit': limit.clamp(1, 50)},
        ),
      );

  Future<PublicProfile> getPublicProfile(String userId) async =>
      PublicProfile.fromJson(await _apiClient.getJson('/users/$userId/public'));

  Future<List<UserSummary>> searchUsers(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final json = await _apiClient.getJson(
      '/users/search',
      queryParameters: {'q': normalized},
    );
    return jsonModelList(json['items'], UserSummary.fromJson);
  }

  Future<List<UserSummary>> getFriends() async {
    final json = await _apiClient.getJson('/users/me/friends');
    return jsonModelList(json['items'], UserSummary.fromJson);
  }

  Future<List<UserSummary>> getFriendRequests() async {
    final json = await _apiClient.getJson('/users/me/friend-requests');
    return jsonModelList(json['items'], UserSummary.fromJson);
  }

  Future<String> sendFriendRequest(String userId) async {
    final json = await _apiClient.postJson('/users/$userId/friend-request');
    final status = jsonNullableString(json['status']) ?? 'pending';
    _apiClient.socialActivity.recordChanged();
    return status == 'pending' ? 'sent' : status;
  }

  Future<String> acceptFriendRequest(String userId) async {
    final json = await _apiClient.postJson('/users/$userId/friend-accept');
    _apiClient.socialActivity.recordChanged();
    return jsonNullableString(json['status']) ?? 'accepted';
  }

  Future<void> removeFriend(String userId) async {
    await _apiClient.deleteJson('/users/$userId/friend');
    _apiClient.socialActivity.recordChanged();
  }

  Future<void> blockUser(String userId) async {
    await _apiClient.postJson('/users/$userId/block');
    _apiClient.socialActivity.recordChanged();
  }

  Future<void> unblockUser(String userId) async {
    await _apiClient.deleteJson('/users/$userId/block');
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

  Future<void> deleteAccount() async {
    await _apiClient.deleteJson('/users/me');
  }
}
