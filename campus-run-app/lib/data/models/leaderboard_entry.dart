/// 排行榜条目。
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
    required this.distanceMeters,
  });

  final int rank;
  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;
  final int distanceMeters;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      distanceMeters: (json['distanceMeters'] as num).toInt(),
    );
  }
}
