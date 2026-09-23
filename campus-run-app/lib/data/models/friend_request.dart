/// 收到的好友申请。
class FriendRequest {
  const FriendRequest({
    required this.requestId,
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
    this.createdAt,
  });

  final int requestId;
  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;
  final String? createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      requestId: (json['requestId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}
