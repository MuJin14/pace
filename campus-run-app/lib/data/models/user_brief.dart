/// 用户简要信息（好友搜索命中结果）。
class UserBrief {
  const UserBrief({
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
  });

  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;

  factory UserBrief.fromJson(Map<String, dynamic> json) {
    return UserBrief(
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}
