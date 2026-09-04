import '../json/json_helpers.dart';
import 'user_models.dart';

enum RankingScope { national, province, city }

class RankingRegion {
  const RankingRegion({required this.province, required this.city});

  factory RankingRegion.fromJson(JsonMap json) => RankingRegion(
    province: jsonString(json['province'], field: 'province'),
    city: jsonString(json['city'], field: 'city'),
  );

  final String province;
  final String city;

  String get key => '$province/$city';

  @override
  bool operator ==(Object other) =>
      other is RankingRegion &&
      other.province == province &&
      other.city == city;

  @override
  int get hashCode => Object.hash(province, city);
}

class RankedRoute {
  const RankedRoute({
    required this.routeId,
    required this.routeName,
    required this.grade,
    required this.color,
    required this.gymId,
    required this.gymName,
    required this.completionCount,
    required this.totalLikes,
    this.coverUrl,
    this.wallZone,
    this.province,
    this.city,
    this.topSendId,
    this.topVideoUrl,
    this.topUserName,
    this.topUserAvatar,
  });

  factory RankedRoute.fromJson(JsonMap json) => RankedRoute(
    routeId: jsonString(json['route_id'], field: 'route_id'),
    routeName: jsonString(json['route_name'], field: 'route_name'),
    grade: jsonString(json['grade'], field: 'grade'),
    color: jsonString(json['color'], field: 'color'),
    coverUrl: jsonNullableString(json['cover_url']),
    wallZone: jsonNullableString(json['wall_zone']),
    province: jsonNullableString(json['province']),
    city: jsonNullableString(json['city']),
    gymId: jsonString(json['gym_id'], field: 'gym_id'),
    gymName: jsonString(json['gym_name'], field: 'gym_name'),
    completionCount: jsonInt(json['completion_count']),
    totalLikes: jsonInt(json['total_likes']),
    topSendId: jsonNullableString(json['top_send_id']),
    topVideoUrl: jsonNullableString(json['top_video_url']),
    topUserName: jsonNullableString(json['top_user_name']),
    topUserAvatar: jsonNullableString(json['top_user_avatar']),
  );

  final String routeId;
  final String routeName;
  final String grade;
  final String color;
  final String? coverUrl;
  final String? wallZone;
  final String? province;
  final String? city;
  final String gymId;
  final String gymName;
  final int completionCount;
  final int totalLikes;
  final String? topSendId;
  final String? topVideoUrl;
  final String? topUserName;
  final String? topUserAvatar;
}

class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.user,
    required this.sendCount,
    required this.totalLikes,
    required this.points,
    required this.maxGrade,
    this.lastSend,
  });

  factory RankingEntry.fromJson(JsonMap json) => RankingEntry(
    rank: jsonInt(json['rank']),
    user: UserSummary.fromJson({
      'id': json['user_id'],
      'nickname': json['nickname'],
      'avatar_url': json['avatar_url'],
    }),
    sendCount: jsonInt(json['send_count']),
    totalLikes: jsonInt(json['total_likes']),
    points: jsonInt(json['points']),
    maxGrade: jsonInt(json['max_grade']),
    lastSend: jsonDateTime(json['last_send']),
  );

  final int rank;
  final UserSummary user;
  final int sendCount;
  final int totalLikes;
  final int points;
  final int maxGrade;
  final DateTime? lastSend;
}

class ScoringRules {
  const ScoringRules({
    required this.completion,
    required this.gradeStep,
    required this.flash,
    required this.like,
  });

  factory ScoringRules.fromJson(JsonMap json) => ScoringRules(
    completion: jsonInt(json['completion']),
    gradeStep: jsonInt(json['gradeStep']),
    flash: jsonInt(json['flash']),
    like: jsonInt(json['like']),
  );

  final int completion;
  final int gradeStep;
  final int flash;
  final int like;
}

class RankingBoard {
  const RankingBoard({required this.items, required this.scoring, this.myRank});

  factory RankingBoard.fromJson(JsonMap json) => RankingBoard(
    items: jsonModelList(json['items'], RankingEntry.fromJson),
    myRank: json['myRank'] == null
        ? null
        : RankingEntry.fromJson(jsonMap(json['myRank'])),
    scoring: ScoringRules.fromJson(jsonMap(json['scoring'])),
  );

  final List<RankingEntry> items;
  final RankingEntry? myRank;
  final ScoringRules scoring;
}
