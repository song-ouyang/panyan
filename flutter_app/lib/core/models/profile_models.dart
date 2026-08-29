import '../json/json_helpers.dart';
import 'user_models.dart';

class GrowthPoint {
  const GrowthPoint({required this.grade, required this.sends, this.month});

  factory GrowthPoint.fromJson(JsonMap json) => GrowthPoint(
    month: jsonDateTime(json['month']),
    grade: jsonString(json['grade'], field: 'grade'),
    sends: jsonInt(json['sends']),
  );

  final DateTime? month;
  final String grade;
  final int sends;
}

class MonthlyDayStat {
  const MonthlyDayStat({
    required this.day,
    required this.gymName,
    required this.grade,
    required this.sends,
  });

  factory MonthlyDayStat.fromJson(JsonMap json) => MonthlyDayStat(
    day: jsonDateTime(json['day']),
    gymName: jsonString(json['gym_name'], field: 'gym_name'),
    grade: jsonString(json['grade'], field: 'grade'),
    sends: jsonInt(json['sends']),
  );

  final DateTime? day;
  final String gymName;
  final String grade;
  final int sends;
}

class MonthlySummary {
  const MonthlySummary({
    required this.climbingDays,
    required this.sends,
    required this.gyms,
    required this.maxGrade,
    required this.flashes,
    required this.videos,
  });

  factory MonthlySummary.fromJson(JsonMap json) => MonthlySummary(
    climbingDays: jsonInt(json['climbing_days']),
    sends: jsonInt(json['sends']),
    gyms: jsonInt(json['gyms']),
    maxGrade: jsonInt(json['max_grade']),
    flashes: jsonInt(json['flashes']),
    videos: jsonInt(json['videos']),
  );

  final int climbingDays;
  final int sends;
  final int gyms;
  final int maxGrade;
  final int flashes;
  final int videos;
}

class GradeSummary {
  const GradeSummary({required this.grade, required this.sends});

  factory GradeSummary.fromJson(JsonMap json) => GradeSummary(
    grade: jsonString(json['grade'], field: 'grade'),
    sends: jsonInt(json['sends']),
  );

  final String grade;
  final int sends;
}

class GymSummary {
  const GymSummary({
    required this.gymId,
    required this.gymName,
    required this.sends,
    this.maxGrade,
  });

  factory GymSummary.fromJson(JsonMap json) => GymSummary(
    gymId: jsonString(json['gym_id'], field: 'gym_id'),
    gymName: jsonString(json['gym_name'], field: 'gym_name'),
    sends: jsonInt(json['sends']),
    maxGrade: json['max_grade'] == null ? null : jsonInt(json['max_grade']),
  );

  final String gymId;
  final String gymName;
  final int sends;
  final int? maxGrade;
}

class MonthDashboard {
  const MonthDashboard({
    required this.month,
    required this.days,
    required this.summary,
    required this.byGrade,
    required this.byGym,
  });

  factory MonthDashboard.fromJson(JsonMap json) => MonthDashboard(
    month: jsonString(json['month'], field: 'month'),
    days: jsonModelList(json['days'], MonthlyDayStat.fromJson),
    summary: MonthlySummary.fromJson(jsonMap(json['summary'])),
    byGrade: jsonModelList(json['byGrade'], GradeSummary.fromJson),
    byGym: jsonModelList(json['byGym'], GymSummary.fromJson),
  );

  final String month;
  final List<MonthlyDayStat> days;
  final MonthlySummary summary;
  final List<GradeSummary> byGrade;
  final List<GymSummary> byGym;
}

class PublicProfile {
  const PublicProfile({
    required this.user,
    required this.stats,
    required this.monthly,
  });

  factory PublicProfile.fromJson(JsonMap json) => PublicProfile(
    user: UserSummary.fromJson(json),
    stats: UserStats.fromJson(jsonMap(json['stats'])),
    monthly: jsonModelList(json['monthly'], PublicMonthlyStat.fromJson),
  );

  final UserSummary user;
  final UserStats stats;
  final List<PublicMonthlyStat> monthly;
}

class PublicMonthlyStat {
  const PublicMonthlyStat({
    required this.month,
    required this.gymName,
    required this.grade,
    required this.sends,
  });

  factory PublicMonthlyStat.fromJson(JsonMap json) => PublicMonthlyStat(
    month: jsonString(json['month'], field: 'month'),
    gymName: jsonString(json['gym_name'], field: 'gym_name'),
    grade: jsonString(json['grade'], field: 'grade'),
    sends: jsonInt(json['sends']),
  );

  final String month;
  final String gymName;
  final String grade;
  final int sends;
}
