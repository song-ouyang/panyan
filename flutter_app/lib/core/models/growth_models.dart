import '../json/json_helpers.dart';

class GrowthLevel {
  const GrowthLevel({
    required this.level,
    required this.name,
    required this.days,
    required this.routes,
    this.badgeKey,
  });
  factory GrowthLevel.fromJson(JsonMap json) => GrowthLevel(
    level: jsonInt(json['level']),
    name: jsonString(json['name'], field: 'name'),
    days: jsonInt(json['days']),
    routes: jsonInt(json['routes']),
    badgeKey: jsonNullableString(json['badgeKey']),
  );
  final int level;
  final String name;
  final int days;
  final int routes;
  final String? badgeKey;
}

class GrowthSnapshot {
  static GrowthSnapshot? optional(Object? value) {
    if (value == null) return null;
    try {
      return GrowthSnapshot.fromJson(jsonMap(value));
    } catch (_) {
      return null;
    }
  }

  const GrowthSnapshot({
    required this.rulesVersion,
    required this.revision,
    required this.currentLevel,
    required this.levelName,
    required this.climbingDays,
    required this.uniqueRoutes,
    required this.remainingDays,
    required this.remainingRoutes,
    this.nextLevel,
    this.backfillStatus = 'complete',
  });
  factory GrowthSnapshot.fromJson(JsonMap json) => GrowthSnapshot(
    rulesVersion: jsonString(json['rulesVersion'], field: 'rulesVersion'),
    revision: jsonInt(json['revision']),
    currentLevel: jsonInt(json['currentLevel']),
    levelName: jsonString(json['levelName'], field: 'levelName'),
    climbingDays: jsonInt(json['climbingDays']),
    uniqueRoutes: jsonInt(json['uniqueRoutes']),
    remainingDays: jsonInt(json['remainingDays']),
    remainingRoutes: jsonInt(json['remainingRoutes']),
    nextLevel: json['nextLevel'] == null
        ? null
        : GrowthLevel.fromJson(jsonMap(json['nextLevel'])),
    backfillStatus: jsonNullableString(json['backfillStatus']) ?? 'complete',
  );
  final String rulesVersion;
  final int revision;
  final int currentLevel;
  final String levelName;
  final int climbingDays;
  final int uniqueRoutes;
  final int remainingDays;
  final int remainingRoutes;
  final GrowthLevel? nextLevel;
  final String backfillStatus;
  double get daysProgress =>
      nextLevel == null ? 1 : (climbingDays / nextLevel!.days).clamp(0, 1);
  double get routesProgress =>
      nextLevel == null ? 1 : (uniqueRoutes / nextLevel!.routes).clamp(0, 1);
}

enum UserBadgeStatus { locked, earned, revoked }

class UserBadge {
  const UserBadge({
    required this.badgeKey,
    required this.level,
    required this.name,
    required this.days,
    required this.routes,
    required this.status,
    this.earnedAt,
  });
  factory UserBadge.fromJson(JsonMap json) => UserBadge(
    badgeKey: jsonString(json['badgeKey'], field: 'badgeKey'),
    level: jsonInt(json['level']),
    name: jsonString(json['name'], field: 'name'),
    days: jsonInt(json['days']),
    routes: jsonInt(json['routes']),
    status: UserBadgeStatus.values.byName(
      jsonString(json['status'], field: 'status'),
    ),
    earnedAt: jsonDateTime(json['earnedAt']),
  );
  final String badgeKey;
  final int level;
  final String name;
  final int days;
  final int routes;
  final UserBadgeStatus status;
  final DateTime? earnedAt;
  String get statusLabel => switch (status) {
    UserBadgeStatus.locked => '待解锁',
    UserBadgeStatus.earned => '已获得',
    UserBadgeStatus.revoked => '记录已撤销',
  };
}

class GrowthPresentation {
  const GrowthPresentation({
    required this.id,
    required this.fromLevel,
    required this.toLevel,
    required this.badgeKeys,
    required this.newBadgeCount,
    required this.levelName,
    required this.growthRevision,
  });
  factory GrowthPresentation.fromJson(JsonMap json) => GrowthPresentation(
    id: jsonString(json['id'], field: 'id'),
    fromLevel: jsonInt(json['fromLevel']),
    toLevel: jsonInt(json['toLevel']),
    badgeKeys: (json['badgeKeys'] as List).cast<String>(),
    newBadgeCount: jsonInt(json['newBadgeCount']),
    levelName: jsonString(json['levelName'], field: 'levelName'),
    growthRevision: jsonInt(json['growthRevision']),
  );
  final String id;
  final int fromLevel;
  final int toLevel;
  final List<String> badgeKeys;
  final int newBadgeCount;
  final String levelName;
  final int growthRevision;
}
