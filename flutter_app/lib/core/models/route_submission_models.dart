import '../json/json_helpers.dart';

enum RoutePointType {
  start,
  hold,
  finish;

  static RoutePointType fromJson(Object? value) => switch (value) {
    'start' => RoutePointType.start,
    'hold' => RoutePointType.hold,
    'finish' => RoutePointType.finish,
    _ => throw FormatException('Unknown route point type: $value'),
  };
}

class RoutePoint {
  const RoutePoint({required this.x, required this.y, required this.type})
    : assert(x >= 0 && x <= 1),
      assert(y >= 0 && y <= 1);

  factory RoutePoint.fromJson(JsonMap json) => RoutePoint(
    x: _requiredDouble(json['x'], field: 'x'),
    y: _requiredDouble(json['y'], field: 'y'),
    type: RoutePointType.fromJson(json['type']),
  );

  final double x;
  final double y;
  final RoutePointType type;

  JsonMap toJson() => {'x': x, 'y': y, 'type': type.name};
}

class RouteSubmissionDraft {
  const RouteSubmissionDraft({
    required this.clientRequestId,
    required this.gymId,
    required this.name,
    required this.grade,
    required this.color,
    required this.coverUrl,
    required this.points,
    this.routeSetId,
    this.wallZone,
    this.videoUrl,
    this.caption,
    this.visibility = 'public',
  });

  final String clientRequestId;
  final String gymId;
  final String? routeSetId;
  final String name;
  final String grade;
  final String color;
  final String? wallZone;
  final String coverUrl;
  final List<RoutePoint> points;
  final String? videoUrl;
  final String? caption;
  final String visibility;

  JsonMap toJson() {
    final normalizedWallZone = wallZone?.trim();
    final normalizedVideoUrl = videoUrl?.trim();
    final normalizedCaption = caption?.trim();
    final hasVideo =
        normalizedVideoUrl != null && normalizedVideoUrl.isNotEmpty;
    return {
      'clientRequestId': clientRequestId,
      'gymId': gymId,
      'routeSetId': routeSetId,
      'name': name.trim(),
      'grade': grade,
      'color': color.trim(),
      if (normalizedWallZone != null && normalizedWallZone.isNotEmpty)
        'wallZone': normalizedWallZone,
      'coverUrl': coverUrl,
      'points': points.map((point) => point.toJson()).toList(growable: false),
      if (hasVideo) 'videoUrl': normalizedVideoUrl,
      if (hasVideo && normalizedCaption != null && normalizedCaption.isNotEmpty)
        'caption': normalizedCaption,
      if (hasVideo) 'visibility': visibility,
    };
  }
}

class RouteSubmission {
  const RouteSubmission({
    required this.id,
    required this.submitterId,
    required this.gymId,
    required this.name,
    required this.grade,
    required this.color,
    required this.coverUrl,
    required this.points,
    required this.status,
    this.routeSetId,
    this.wallZone,
    this.reviewNote,
    this.reviewedAt,
    this.createdAt,
    this.gymName,
    this.publishedRouteId,
    this.sendId,
    this.videoModerationStatus,
  });

  factory RouteSubmission.fromJson(JsonMap json) {
    final send = json['send'];
    final sendJson = send is Map<String, dynamic> ? send : null;
    return RouteSubmission(
      id: jsonString(json['id'], field: 'id'),
      submitterId: jsonString(json['submitter_id'], field: 'submitter_id'),
      gymId: jsonString(json['gym_id'], field: 'gym_id'),
      routeSetId: jsonNullableString(json['route_set_id']),
      name: jsonString(json['name'], field: 'name'),
      grade: jsonString(json['grade'], field: 'grade'),
      color: jsonString(json['color'], field: 'color'),
      wallZone: jsonNullableString(json['wall_zone']),
      coverUrl: jsonString(json['cover_url'], field: 'cover_url'),
      points: jsonModelList(json['points'], RoutePoint.fromJson),
      status: jsonString(json['status'], field: 'status'),
      reviewNote: jsonNullableString(json['review_note']),
      reviewedAt: jsonDateTime(json['reviewed_at']),
      createdAt: jsonDateTime(json['created_at']),
      gymName: jsonNullableString(json['gym_name']),
      publishedRouteId: jsonNullableString(json['published_route_id']),
      sendId: jsonNullableString(json['send_id']),
      videoModerationStatus:
          jsonNullableString(json['videoModerationStatus']) ??
          jsonNullableString(json['video_moderation_status']) ??
          jsonNullableString(json['send_moderation_status']) ??
          jsonNullableString(sendJson?['moderation_status']) ??
          jsonNullableString(sendJson?['moderationStatus']),
    );
  }

  final String id;
  final String submitterId;
  final String gymId;
  final String? routeSetId;
  final String name;
  final String grade;
  final String color;
  final String? wallZone;
  final String coverUrl;
  final List<RoutePoint> points;
  final String status;
  final String? reviewNote;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final String? gymName;
  final String? publishedRouteId;
  final String? sendId;
  final String? videoModerationStatus;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

double _requiredDouble(Object? value, {required String field}) {
  final parsed = jsonNullableDouble(value);
  if (parsed == null) throw FormatException('$field must be a number');
  return parsed;
}
