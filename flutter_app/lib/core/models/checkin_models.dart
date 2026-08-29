import '../json/json_helpers.dart';

class CheckinMilestone {
  const CheckinMilestone({required this.type, required this.grade});

  factory CheckinMilestone.fromJson(JsonMap json) => CheckinMilestone(
    type: jsonString(json['type'], field: 'type'),
    grade: jsonString(json['grade'], field: 'grade'),
  );

  final String type;
  final String grade;
}

class CheckinResult {
  const CheckinResult({
    required this.sendId,
    required this.moderationStatus,
    required this.pointsEarned,
    required this.pendingPoints,
    this.milestone,
  });

  factory CheckinResult.fromJson(JsonMap json) => CheckinResult(
    sendId: jsonString(json['sendId'], field: 'sendId'),
    moderationStatus: jsonString(
      json['moderationStatus'],
      field: 'moderationStatus',
    ),
    pointsEarned: jsonInt(json['pointsEarned']),
    pendingPoints: jsonInt(json['pendingPoints']),
    milestone: json['milestone'] == null
        ? null
        : CheckinMilestone.fromJson(jsonMap(json['milestone'])),
  );

  final String sendId;
  final String moderationStatus;
  final int pointsEarned;
  final int pendingPoints;
  final CheckinMilestone? milestone;
}

class MultipartUploadTask {
  const MultipartUploadTask({
    required this.key,
    required this.uploadId,
    required this.partSize,
    required this.size,
  });

  factory MultipartUploadTask.fromJson(JsonMap json) => MultipartUploadTask(
    key: jsonString(json['key'], field: 'key'),
    uploadId: jsonString(json['uploadId'], field: 'uploadId'),
    partSize: jsonInt(json['partSize']),
    size: jsonInt(json['size']),
  );

  final String key;
  final String uploadId;
  final int partSize;
  final int size;
}

class UploadedPart {
  const UploadedPart({required this.number, required this.etag});

  final int number;
  final String etag;

  JsonMap toJson() => {'number': number, 'etag': etag};
}
