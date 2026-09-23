/// 我获得的勋章。
class UserBadge {
  const UserBadge({
    required this.badgeId,
    required this.code,
    required this.name,
    this.icon,
    this.description,
    this.awardedAt,
  });

  final int badgeId;
  final String code;
  final String name;
  final String? icon;
  final String? description;
  final String? awardedAt;

  factory UserBadge.fromJson(Map<String, dynamic> json) {
    return UserBadge(
      badgeId: (json['badgeId'] as num).toInt(),
      code: json['code'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      awardedAt: json['awardedAt'] as String?,
    );
  }
}
