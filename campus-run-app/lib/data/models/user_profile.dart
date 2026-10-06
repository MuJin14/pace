/// 用户主页信息（查看他人 / 查看自己，类似微信个人资料页）。
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.uniqueId,
    required this.nickname,
    this.avatarUrl,
    this.gender,
    this.age,
    this.createdAt,
    this.relation = 'none',
    this.totalDistanceMeters = 0,
    this.totalActivityCount = 0,
    this.streakDays = 0,
  });

  final int userId;
  final String uniqueId;
  final String nickname;
  final String? avatarUrl;

  /// 性别：0=保密 1=男 2=女；**null 表示对方未公开或未填写**。
  ///
  /// 后端按对方的可见性设置决定是否返回：不公开时字段就是 null，
  /// 所以前端**不需要**再判断可见性开关，只判断「有没有值」即可 ——
  /// 这样「不公开」在客户端根本无法被反推出来。
  final int? gender;

  /// 年龄；null 表示对方未公开或未填写。
  final int? age;

  final String? createdAt;

  /// 与当前登录用户的关系：self / friend / pending_outgoing / pending_incoming / none。
  /// 用它决定操作按钮，避免前端自己推断导致规则不一致。
  final String relation;

  final int totalDistanceMeters;
  final int totalActivityCount;
  final int streakDays;

  bool get isSelf => relation == 'self';
  bool get isFriend => relation == 'friend';
  bool get isPendingOutgoing => relation == 'pending_outgoing';
  bool get isPendingIncoming => relation == 'pending_incoming';

  /// 性别展示文案；未公开或未填写时返回 null。
  String? get genderLabel => switch (gender) {
        1 => '男',
        2 => '女',
        _ => null,
      };

  /// 是否应在主页展示性别/年龄行（任一有值就展示）。
  bool get hasPublicProfileInfo => genderLabel != null || age != null;

  /// 关系的中文说明（主页顶部展示）。
  String get relationLabel => switch (relation) {
        'self' => '这是你自己',
        'friend' => '已是好友',
        'pending_outgoing' => '已发送好友申请，等待对方通过',
        'pending_incoming' => '对方已向你发送好友申请',
        _ => '还不是好友',
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: (json['userId'] as num).toInt(),
      uniqueId: json['uniqueId'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      // null 表示对方未公开/未填写 —— 直接保留 null，不要兜底成 0
      gender: (json['gender'] as num?)?.toInt(),
      age: (json['age'] as num?)?.toInt(),
      createdAt: json['createdAt'] as String?,
      relation: (json['relation'] as String?) ?? 'none',
      totalDistanceMeters: (json['totalDistanceMeters'] as num?)?.toInt() ?? 0,
      totalActivityCount: (json['totalActivityCount'] as num?)?.toInt() ?? 0,
      streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
    );
  }
}
