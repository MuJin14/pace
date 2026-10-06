import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用卡片：白底、圆角 16、极轻阴影、统一内边距；可选点击态与 margin。
///
/// 需要首页规格里的「工作台白卡」请直接用 [AppDashboardCard]；
/// 需要更强/更弱的圆角时传 [radius]，需要极浅描边时传 [borderColor]，
/// 需要高亮某一行（如排行榜里的「我」）时传 [color]。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.margin,
    this.radius = AppRadius.md,
    this.borderColor,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  /// 圆角，默认 16（[AppRadius.md]）
  final double radius;

  /// 描边颜色；为空时不描边
  final Color? borderColor;

  /// 背景色；为空时用 [AppColors.card]（标准白卡）
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final background = color ?? AppColors.card;
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );

    final Widget card = onTap == null
        ? Container(
            decoration: BoxDecoration(
              color: background,
              borderRadius: borderRadius,
              boxShadow: AppShadows.card,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor!, width: 1),
            ),
            child: content,
          )
        : Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: borderColor == null
                  ? BorderSide.none
                  : BorderSide(color: borderColor!, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: content,
            ),
          );

    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
