import '../json/json_helpers.dart';

class UserSummary {
  const UserSummary({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.role,
    this.friendship,
    this.createdAt,
    this.profileCompleted = true,
  });

  factory UserSummary.fromJson(JsonMap json) => UserSummary(
    id: jsonString(json['id'], field: 'id'),
    nickname: jsonNullableString(json['nickname']) ?? '岩友',
    avatarUrl:
        jsonNullableString(json['avatar_url']) ??
        jsonNullableString(json['avatarUrl']),
    bio: jsonNullableString(json['bio']),
    role: jsonNullableString(json['role']),
    friendship: jsonNullableString(json['friendship']),
    createdAt: jsonDateTime(json['created_at']),
    profileCompleted:
        json.containsKey('profile_completed') ||
            json.containsKey('profileCompleted')
        ? json['profile_completed'] == true || json['profileCompleted'] == true
        : true,
  );

  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final String? role;
  final String? friendship;
  final DateTime? createdAt;
  final bool profileCompleted;

  JsonMap toJson() => {
    'id': id,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'role': role,
    'friendship': friendship,
    'createdAt': createdAt?.toIso8601String(),
    'profileCompleted': profileCompleted,
  };
}

class UserStats {
  const UserStats({
    required this.totalSends,
    required this.gymCount,
    required this.maxGrade,
    required this.monthlySends,
    required this.monthlyMaxGrade,
  });

  factory UserStats.fromJson(JsonMap json) => UserStats(
    totalSends: jsonInt(json['total_sends']),
    gymCount: jsonInt(json['gym_count']),
    maxGrade: jsonInt(json['max_grade']),
    monthlySends: jsonInt(json['monthly_sends']),
    monthlyMaxGrade: jsonInt(json['monthly_max_grade']),
  );

  final int totalSends;
  final int gymCount;
  final int maxGrade;
  final int monthlySends;
  final int monthlyMaxGrade;
}

class UserProfile {
  const UserProfile({required this.user, required this.stats});

  factory UserProfile.fromJson(JsonMap json) => UserProfile(
    user: UserSummary.fromJson(json),
    stats: UserStats.fromJson(jsonMap(json['stats'])),
  );

  final UserSummary user;
  final UserStats stats;
}
