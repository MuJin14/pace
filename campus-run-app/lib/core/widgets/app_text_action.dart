import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 文字动作（文字链）：如「查看全部」「去跑步」「设置目标」等轻量操作。
///
/// 首页规格中「去跑步」「查看全部」都是纯文字动作（12.6/700 主色）；
/// 需要按钮观感时用 [AppEmptyHint] 的 actionLabel（橙色胶囊按钮）。
class AppTextAction extends StatelessWidget {
  const AppTextAction({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.color = AppColors.accentHot,
    this.fontSize = AppFontSize.label,
    this.fontWeight = AppFontWeight.bold,
    this.iconSize = 14,
    this.underline = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// 可选前置图标（如 `Icons.directions_run`）
  final IconData? icon;

  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final double iconSize;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      splashColor: color.withValues(alpha: 0.15),
      highlightColor: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: color),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
                decoration: underline ? TextDecoration.underline : null,
                decorationColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
