import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';

/// 工作台白卡：白底 + 16 圆角 + 极轻阴影 + 16 内边距。
///
/// 即首页规格里的卡片容器（替代页面内私有的 `_cardDecoration`），
/// 供首页各区块与其它页面复用。传 [gradientColors] 时切换为渐变卡片
/// （Hero 今日目标卡：24 圆角 + 橙色柔和阴影，135° 左上→右下）。
class AppDashboardCard extends StatelessWidget {
  const AppDashboardCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.margin,
    this.radius = AppRadius.md,
    this.borderColor,
    this.gradientColors,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  /// 圆角，默认 16（白卡）；Hero 渐变卡用 24（[AppRadius.lg]）
  final double radius;

  /// 极浅描边（如空态卡片）；为空时不描边
  final Color? borderColor;

  /// 传值则渲染为渐变卡（推荐 [AppColors.heroGradient]）
  final List<Color>? gradientColors;

  /// 覆盖默认阴影；为空时白卡用 [AppShadows.card]，渐变卡用橙色柔光
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors;
    if (colors == null || colors.isEmpty) {
      return AppCard(
        padding: padding,
        onTap: onTap,
        margin: margin,
        radius: radius,
        borderColor: borderColor,
        child: child,
      );
    }

    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );
    final shadow = boxShadow ??
        const [
          BoxShadow(
            color: AppColors.heroShadow,
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ];

    final Widget card = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadius,
        boxShadow: shadow,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: borderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: content,
              ),
            ),
    );

    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
