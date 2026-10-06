import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 环比 chip：正负配色 + 胶囊底。
///
/// 首页规格：字号 10.6/700，绿底 #EAF6EF、正向文字 #2FA36B；
/// 负向沿用危险色（底色为派生的浅红 [AppColors.chipRedBg]）。
class AppDeltaChip extends StatelessWidget {
  const AppDeltaChip({
    super.key,
    required this.text,
    this.positive = true,
    this.background,
    this.foreground,
    this.fontSize = AppFontSize.tiny,
    this.showIcon = false,
    this.iconSize = AppFontSize.caption,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
  });

  /// 文案，如 `+1.2 km`
  final String text;

  /// 是否为正向（正向绿、负向红）
  final bool positive;

  /// 覆盖底色
  final Color? background;

  /// 覆盖文字色
  final Color? foreground;

  final double fontSize;

  /// 是否显示上升/下降小箭头
  final bool showIcon;
  final double iconSize;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? (positive ? AppColors.deltaUp : AppColors.danger);
    final bg = background ?? (positive ? AppColors.chipGreenBg : AppColors.chipRedBg);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: iconSize,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: AppFontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
