/// 好友列表条目。
class FriendItem {
  const FriendItem({
    required this.friendshipId,
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
    this.createdAt,
  });

  final int friendshipId;
  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;
  final String? createdAt;

  factory FriendItem.fromJson(Map<String, dynamic> json) {
    return FriendItem(
      friendshipId: (json['friendshipId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}
