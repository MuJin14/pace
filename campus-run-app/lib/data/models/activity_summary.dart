/// 运动记录摘要，对应 `GET /api/v1/activity` 的列表项字段。
class ActivitySummary {
  const ActivitySummary({
    required this.activityId,
    required this.type,
    this.mode,
    this.invalid,
    required this.distanceMeters,
    required this.durationSeconds,
    this.avgSpeed,
    this.avgPace,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
  });

  final int activityId;

  /// 运动类型：1=跑步 2=骑行
  final int type;

  /// 运动模式（专属模式扩展字段，后端已预留）
  final int? mode;

  /// 是否无效（防作弊判定，1=无效）
  final int? invalid;
  final int distanceMeters;
  final int durationSeconds;
  final double? avgSpeed;
  final int? avgPace;
  final String startTime;
  final String endTime;
  final String createdAt;

  bool get isRunning => type == 1;

  factory ActivitySummary.fromJson(Map<String, dynamic> json) {
    return ActivitySummary(
      activityId: (json['activityId'] as num).toInt(),
      type: (json['type'] as num).toInt(),
      mode: (json['mode'] as num?)?.toInt(),
      invalid: (json['invalid'] as num?)?.toInt(),
      distanceMeters: (json['distanceMeters'] as num).toInt(),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      avgSpeed: (json['avgSpeed'] as num?)?.toDouble(),
      avgPace: (json['avgPace'] as num?)?.toInt(),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}
