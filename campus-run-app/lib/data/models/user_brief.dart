/// 用户简要信息（好友搜索命中结果）。
class UserBrief {
  const UserBrief({
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
    this.relation = 'none',
  });

  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;

  /// 与当前登录用户的关系：self / friend / pending_outgoing / pending_incoming / none。
  final String relation;

  bool get isSelf => relation == 'self';
  bool get isFriend => relation == 'friend';
  bool get isPendingOutgoing => relation == 'pending_outgoing';
  bool get isPendingIncoming => relation == 'pending_incoming';

  factory UserBrief.fromJson(Map<String, dynamic> json) {
    return UserBrief(
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      relation: (json['relation'] as String?) ?? 'none',
    );
  }
}
