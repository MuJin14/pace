/// 密码重置申请（用户自助发起，管理员处理）。
class PasswordResetRequestItem {
  const PasswordResetRequestItem({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.phone,
    required this.status,
    this.note,
    this.createdAt,
    this.handledAt,
  });

  /// 状态常量与服务端 `PasswordResetRequest` 保持一致。
  static const int statusPending = 0;
  static const int statusReset = 1;
  static const int statusRejected = 2;

  final int id;
  final int userId;
  final String nickname;
  final String phone;
  final int status;
  final String? note;
  final String? createdAt;
  final String? handledAt;

  bool get isPending => status == statusPending;

  /// 状态中文说明。
  String get statusLabel => switch (status) {
        statusPending => '待处理',
        statusReset => '已重置',
        statusRejected => '已拒绝',
        _ => '未知',
      };

  factory PasswordResetRequestItem.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequestItem(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      nickname: (json['nickname'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      status: (json['status'] as num?)?.toInt() ?? statusPending,
      note: json['note'] as String?,
      createdAt: json['createdAt'] as String?,
      handledAt: json['handledAt'] as String?,
    );
  }
}
