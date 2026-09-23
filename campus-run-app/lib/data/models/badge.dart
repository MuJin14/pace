/// 勋章（含是否已获得）。
class Badge {
  const Badge({
    required this.id,
    required this.code,
    required this.name,
    this.icon,
    this.description,
    this.ruleType,
    this.ruleValue,
    this.earned = false,
    this.awardedAt,
  });

  final int id;
  final String code;
  final String name;
  final String? icon;
  final String? description;
  final String? ruleType;
  final int? ruleValue;
  final bool earned;
  final String? awardedAt;

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      ruleType: json['ruleType'] as String?,
      ruleValue: (json['ruleValue'] as num?)?.toInt(),
      earned: json['earned'] as bool? ?? false,
      awardedAt: json['awardedAt'] as String?,
    );
  }
}
