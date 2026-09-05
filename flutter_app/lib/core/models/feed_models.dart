import '../json/json_helpers.dart';
import 'user_models.dart';

class FeedComment {
  const FeedComment({
    required this.id,
    required this.content,
    required this.user,
    this.createdAt,
    this.moderationStatus,
  });

  factory FeedComment.fromJson(JsonMap json) => FeedComment(
    id: jsonString(json['id'], field: 'id'),
    content: jsonString(json['content'], field: 'content'),
    user: UserSummary.fromJson({
      'id': json['user_id'],
      'nickname': json['nickname'],
      'avatar_url': json['avatar_url'],
    }),
    createdAt: jsonDateTime(json['created_at']),
    moderationStatus: jsonNullableString(json['moderation_status']),
  );

  final String id;
  final String content;
  final UserSummary user;
  final DateTime? createdAt;
  final String? moderationStatus;

  bool get isPending => moderationStatus == 'pending';
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.attempts,
    required this.imageUrls,
    required this.likeCount,
    required this.commentCount,
    required this.liked,
    required this.comments,
    this.user,
    this.routeId,
    this.routeName,
    this.grade,
    this.color,
    this.gymId,
    this.gymName,
    this.videoUrl,
    this.caption,
    this.visibility,
    this.moderationStatus,
    this.sentAt,
  });

  factory FeedPost.fromJson(JsonMap json) => FeedPost(
    id: jsonString(json['id'], field: 'id'),
    user: json['user_id'] == null
        ? null
        : UserSummary.fromJson({
            'id': json['user_id'],
            'nickname': json['nickname'],
            'avatar_url': json['avatar_url'],
          }),
    routeId: jsonNullableString(json['route_id']),
    routeName: jsonNullableString(json['route_name']),
    grade: jsonNullableString(json['grade']),
    color: jsonNullableString(json['color']),
    gymId: jsonNullableString(json['gym_id']),
    gymName: jsonNullableString(json['gym_name']),
    attempts: jsonInt(json['attempts'], fallback: 1),
    videoUrl: jsonNullableString(json['video_url']),
    imageUrls: jsonStringList(json['image_urls']),
    caption: jsonNullableString(json['caption']),
    visibility: jsonNullableString(json['visibility']),
    moderationStatus: jsonNullableString(json['moderation_status']),
    sentAt: jsonDateTime(json['sent_at']),
    likeCount: jsonInt(json['like_count']),
    commentCount: jsonInt(json['comment_count']),
    liked: jsonBool(json['liked']),
    comments: jsonModelList(json['comments'], FeedComment.fromJson),
  );

  final String id;
  final UserSummary? user;
  final String? routeId;
  final String? routeName;
  final String? grade;
  final String? color;
  final String? gymId;
  final String? gymName;
  final int attempts;
  final String? videoUrl;
  final List<String> imageUrls;
  final String? caption;
  final String? visibility;
  final String? moderationStatus;
  final DateTime? sentAt;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final List<FeedComment> comments;

  bool get isMoment => routeId == null;
}

class MyPost {
  const MyPost({
    required this.id,
    required this.attempts,
    required this.imageUrls,
    required this.visibility,
    required this.moderationStatus,
    this.videoUrl,
    this.caption,
    this.sentAt,
    this.routeId,
    this.routeName,
    this.grade,
    this.gymName,
  });

  factory MyPost.fromJson(JsonMap json) => MyPost(
    id: jsonString(json['id'], field: 'id'),
    attempts: jsonInt(json['attempts'], fallback: 1),
    videoUrl: jsonNullableString(json['video_url']),
    imageUrls: jsonStringList(json['image_urls']),
    caption: jsonNullableString(json['caption']),
    visibility: jsonNullableString(json['visibility']) ?? 'private',
    moderationStatus:
        jsonNullableString(json['moderation_status']) ?? 'pending',
    sentAt: jsonDateTime(json['sent_at']),
    routeId: jsonNullableString(json['route_id']),
    routeName: jsonNullableString(json['route_name']),
    grade: jsonNullableString(json['grade']),
    gymName: jsonNullableString(json['gym_name']),
  );

  final String id;
  final int attempts;
  final String? videoUrl;
  final List<String> imageUrls;
  final String? caption;
  final String visibility;
  final String moderationStatus;
  final DateTime? sentAt;
  final String? routeId;
  final String? routeName;
  final String? grade;
  final String? gymName;

  bool get isMoment => routeId == null;
}

class FeedPage {
  const FeedPage({required this.items, this.nextCursor});

  factory FeedPage.fromJson(JsonMap json) => FeedPage(
    items: jsonModelList(json['items'], FeedPost.fromJson),
    nextCursor: jsonNullableString(json['nextCursor']),
  );

  final List<FeedPost> items;
  final String? nextCursor;
}

class RouteLeaderboardEntry {
  const RouteLeaderboardEntry({required this.rank, required this.post});

  factory RouteLeaderboardEntry.fromJson(JsonMap json) => RouteLeaderboardEntry(
    rank: jsonInt(json['rank']),
    post: FeedPost.fromJson(json),
  );

  final int rank;
  final FeedPost post;
}

class RouteLeaderboard {
  const RouteLeaderboard({required this.items, required this.completionCount});

  factory RouteLeaderboard.fromJson(JsonMap json) => RouteLeaderboard(
    items: jsonModelList(json['items'], RouteLeaderboardEntry.fromJson),
    completionCount: jsonInt(json['completionCount']),
  );

  final List<RouteLeaderboardEntry> items;
  final int completionCount;
}
