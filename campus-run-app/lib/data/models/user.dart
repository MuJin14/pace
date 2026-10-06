/// 用户信息，与后端 `/user/me` 及登录/注册响应的 `data` 字段对应。
class User {
  const User({
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    required this.phone,
    this.avatarUrl,
    this.gender,
    this.age,
    this.genderPublic = false,
    this.agePublic = false,
    this.role = 0,
    this.createdAt,
  });

  final int userId;
  final String uniqueId;
  final String nickname;
  final String phone;
  final String? avatarUrl;

  /// 性别：0=保密 1=男 2=女；null=未填写。
  final int? gender;

  /// 年龄；null=未填写。
  final int? age;

  /// 性别是否对他人公开。默认 false —— 与后端保持一致：隐私默认关闭。
  final bool genderPublic;

  /// 年龄是否对他人公开。
  final bool agePublic;

  /// 角色：0=普通用户 1=管理员。
  ///
  /// 前端只用它决定是否显示「管理后台」入口。**不是安全边界** ——
  /// 篡改这个值也调不动管理员接口，真正的校验在服务端 `@PreAuthorize`。
  final int role;

  final String? createdAt;

  bool get isAdmin => role == 1;

  /// 性别展示文案；未填写或保密时返回 null（调用方据此决定是否渲染该行）。
  String? get genderLabel => switch (gender) {
        1 => '男',
        2 => '女',
        _ => null,
      };

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      phone: json['phone'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      gender: (json['gender'] as num?)?.toInt(),
      age: (json['age'] as num?)?.toInt(),
      // 后端返回布尔值；缺省按 false（不公开），与「隐私默认关闭」一致
      genderPublic: json['genderPublic'] as bool? ?? false,
      agePublic: json['agePublic'] as bool? ?? false,
      // 缺省 0（普通用户）：老接口不返回该字段时不能把所有人当管理员
      role: (json['role'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }
}
