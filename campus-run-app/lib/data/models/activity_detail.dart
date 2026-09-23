import 'track_point.dart';

/// 运动记录详情，对应 `GET /api/v1/activity/{id}`。
class ActivityDetail {
  const ActivityDetail({
    required this.activityId,
    required this.type,
    this.mode,
    this.invalid,
    required this.distanceMeters,
    required this.durationSeconds,
    this.avgSpeed,
    this.avgPace,
    this.calories,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
    this.track = const [],
  });

  final int activityId;
  final int type;
  final int? mode;
  final int? invalid;
  final int distanceMeters;
  final int durationSeconds;
  final double? avgSpeed;
  final int? avgPace;
  final double? calories;
  final String startTime;
  final String endTime;
  final String createdAt;
  final List<TrackPoint> track;

  bool get isRunning => type == 1;

  factory ActivityDetail.fromJson(Map<String, dynamic> json) {
    final rawTrack = json['track'] as List<dynamic>? ?? const [];
    return ActivityDetail(
      activityId: (json['activityId'] as num).toInt(),
      type: (json['type'] as num).toInt(),
      mode: (json['mode'] as num?)?.toInt(),
      invalid: (json['invalid'] as num?)?.toInt(),
      distanceMeters: (json['distanceMeters'] as num).toInt(),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      avgSpeed: (json['avgSpeed'] as num?)?.toDouble(),
      avgPace: (json['avgPace'] as num?)?.toInt(),
      calories: (json['calories'] as num?)?.toDouble(),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      createdAt: json['createdAt'] as String,
      track: rawTrack
          .map((e) => TrackPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
