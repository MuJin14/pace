import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 大数字 + 单位 + 可选标签。
///
/// 首页规格取值：
/// - Hero 主数字 39.6/700，单位 15.6/600（白 70%），小标题 12.6/500；
/// - 三栏统计数字 23.6/700，标签 11.6/400。
///
/// 深色（Hero）场景传 `color: Colors.white`，单位与标签自动取 70% 透明度；
/// 也可用 [unitColor] / [labelColor] 单独覆盖。
class AppMetricText extends StatelessWidget {
  const AppMetricText({
    super.key,
    required this.value,
    this.unit,
    this.label,
    this.valueSize = AppFontSize.metric,
    this.unitSize = AppFontSize.unit,
    this.labelSize = AppFontSize.hint,
    this.color = AppColors.textPrimary,
    this.unitColor,
    this.labelColor,
    this.valueWeight = AppFontWeight.bold,
    this.unitWeight = AppFontWeight.bold,
    this.labelWeight = AppFontWeight.regular,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.labelGap = AppSpacing.gap6,
    this.labelAbove = false,
    this.maxLines = 1,
    this.textAlign,
  });

  /// 数字文本（如 `5.2`）
  final String value;

  /// 单位（如 `km` / `分:秒` / `%`）
  final String? unit;

  /// 可选标签（如 `距离 (km)`）
  final String? label;

  final double valueSize;
  final double unitSize;
  final double labelSize;

  /// 数字与单位颜色；单位默认取该色 70% 透明度
  final Color color;

  /// 单位颜色，覆盖默认派生值
  final Color? unitColor;

  /// 标签颜色，覆盖默认派生值（默认 [color] 70%）
  final Color? labelColor;

  final FontWeight valueWeight;
  final FontWeight unitWeight;
  final FontWeight labelWeight;

  final CrossAxisAlignment crossAxisAlignment;

  /// 数字与标签之间的间距
  final double labelGap;

  /// 标签是否放在数字上方（Hero 小标题在数字上方时为 true）
  final bool labelAbove;

  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final unitFg = unitColor ?? color.withValues(alpha: 0.7);
    final labelFg = labelColor ?? color.withValues(alpha: 0.7);

    // 用 Text.rich 让数字与单位共享基线，避免 Row 在无界宽度下报错。
    final number = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: valueWeight,
              color: color,
              height: 1,
            ),
          ),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: TextStyle(
                fontSize: unitSize,
                fontWeight: unitWeight,
                color: unitFg,
                height: 1,
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );

    if (label == null) return number;

    final labelText = Text(
      label!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: labelSize,
        fontWeight: labelWeight,
        color: labelFg,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (labelAbove) ...[
          labelText,
          SizedBox(height: labelGap),
          number,
        ] else ...[
          number,
          SizedBox(height: labelGap),
          labelText,
        ],
      ],
    );
  }
}
