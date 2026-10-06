/// 管理后台的用户列表项。
///
/// **刻意没有密码字段** —— 管理员需要的是「找到人 + 重置密码」，
/// 不该拿到任何口令信息。后端 DTO 同样没有，并有测试用反射兜底防回归。
class AdminUser {
  const AdminUser({
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    required this.phone,
    this.avatarUrl,
    this.role = 0,
    this.createdAt,
  });

  final int userId;
  final String uniqueId;
  final String nickname;
  final String phone;
  final String? avatarUrl;

  /// 0=普通用户 1=管理员。
  final int role;

  final String? createdAt;

  bool get isAdmin => role == 1;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      userId: (json['userId'] as num).toInt(),
      uniqueId: (json['uniqueId'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      role: (json['role'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }
}
