/// 运动目标。
class Goal {
  const Goal({
    required this.id,
    required this.periodType,
    required this.targetDistanceMeters,
    required this.currentDistanceMeters,
    this.startDate,
    this.endDate,
    this.status = 0,
    this.createdAt,
  });

  final int id;
  final String periodType;
  final int targetDistanceMeters;
  final int currentDistanceMeters;
  final String? startDate;
  final String? endDate;

  /// 0=进行中 1=已完成 2=已过期 3=已取消
  final int status;
  final String? createdAt;

  double get progress {
    if (targetDistanceMeters <= 0) return 0;
    return (currentDistanceMeters / targetDistanceMeters).clamp(0.0, 1.0);
  }

  bool get isActive => status == 0;

  String get statusLabel {
    switch (status) {
      case 1:
        return '已完成';
      case 2:
        return '已过期';
      case 3:
        return '已取消';
      default:
        return '进行中';
    }
  }

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: (json['id'] as num).toInt(),
      periodType: json['periodType'] as String,
      targetDistanceMeters: (json['targetDistanceMeters'] as num).toInt(),
      currentDistanceMeters: (json['currentDistanceMeters'] as num).toInt(),
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      status: (json['status'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }
}
