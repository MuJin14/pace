/// 个人排名，对应 `GET /api/v1/leaderboard/my-rank`。
class MyRank {
  const MyRank({
    this.rank,
    required this.distanceMeters,
    required this.total,
  });

  final int? rank;
  final int distanceMeters;
  final int total;

  factory MyRank.fromJson(Map<String, dynamic> json) {
    return MyRank(
      rank: (json['rank'] as num?)?.toInt(),
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}
