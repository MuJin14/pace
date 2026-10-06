/// 排行榜条目。
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
    required this.distanceMeters,
    this.relation = 'none',
    this.gapToAheadMeters,
    this.gapToBehindMeters,
  });

  final int rank;
  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;
  final int distanceMeters;

  /// 与当前登录用户的关系：self / friend / pending_outgoing / pending_incoming / none。
  /// 决定榜上「加好友」按钮显示什么。
  final String relation;

  /// 与上一名的距离差（米）。第 1 名为 null。
  final int? gapToAheadMeters;

  /// 与下一名的距离差（米）。最后一名为 null。
  final int? gapToBehindMeters;

  bool get isSelf => relation == 'self';
  bool get isFriend => relation == 'friend';
  bool get isPendingOutgoing => relation == 'pending_outgoing';
  bool get isPendingIncoming => relation == 'pending_incoming';

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      distanceMeters: (json['distanceMeters'] as num).toInt(),
      relation: (json['relation'] as String?) ?? 'none',
      gapToAheadMeters: (json['gapToAheadMeters'] as num?)?.toInt(),
      gapToBehindMeters: (json['gapToBehindMeters'] as num?)?.toInt(),
    );
  }
}
