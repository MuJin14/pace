/// 用户信息，与后端 `/user/me` 及登录/注册响应的 `data` 字段对应。
class User {
  const User({
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    required this.phone,
    this.avatarUrl,
    this.createdAt,
  });

  final int userId;
  final String uniqueId;
  final String nickname;
  final String phone;
  final String? avatarUrl;
  final String? createdAt;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      phone: json['phone'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}
