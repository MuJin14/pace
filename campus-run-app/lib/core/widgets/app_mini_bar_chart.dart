import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 7 柱迷你柱状图（本周跑量）：支持高亮某一天、未来日、空态。
///
/// 首页规格：柱宽 24、圆角 6、今日 [AppColors.accentHot]、已过 [AppColors.barPast]、
/// 未跑 / 未来 [AppColors.barEmpty]；日期标签 9.6，今日橙色加粗。
/// 柱高 = [minBarHeight] + 值 / 最大值 × ([maxBarHeight] - [minBarHeight])，
/// 空数据时保留 [minBarHeight] 空柱骨架。
class AppMiniBarChart extends StatelessWidget {
  const AppMiniBarChart({
    super.key,
    required this.values,
    this.labels,
    this.highlightIndex,
    this.futureFromIndex,
    this.maxValue,
    this.barWidth = 24,
    this.minBarHeight = AppSpacing.xs,
    this.maxBarHeight = 44,
    this.barRadius = AppRadius.xxs,
    this.activeColor = AppColors.accentHot,
    this.pastColor = AppColors.barPast,
    this.emptyColor = AppColors.barEmpty,
    this.labelSize = AppFontSize.micro,
    this.labelColor = AppColors.textHint,
    this.highlightLabelColor = AppColors.accentHot,
    this.labelGap = AppSpacing.gap6,
    this.showLabels = true,
    this.empty,
  });

  /// 每日数值（单位无关，7 个为本周一周七天）
  final List<int> values;

  /// 日期标签；为空且 [values] 长度为 7 时使用 [weekLabels]
  final List<String>? labels;

  /// 高亮下标（通常是今天）
  final int? highlightIndex;

  /// 从该下标起视为未来日（画空柱）；为空但给了 [highlightIndex] 时，
  /// 默认把 [highlightIndex] 之后的下标视为未来日
  final int? futureFromIndex;

  /// 显式最大高度基准值（保持柱高比例稳定时用）
  final int? maxValue;

  final double barWidth;
  final double minBarHeight;
  final double maxBarHeight;
  final double barRadius;

  final Color activeColor;
  final Color pastColor;
  final Color emptyColor;

  final double labelSize;
  final Color labelColor;
  final Color highlightLabelColor;
  final double labelGap;
  final bool showLabels;

  /// 全部为 0 时的替代内容（为空则保留空柱骨架，符合首页规格）
  final Widget? empty;

  /// 默认星期标签
  static const List<String> weekLabels = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return empty ?? const SizedBox.shrink();

    final effectiveMax =
        maxValue ?? values.fold<int>(0, (a, b) => a > b ? a : b);
    if (empty != null && effectiveMax <= 0) return empty!;

    final futureStart =
        futureFromIndex ?? (highlightIndex == null ? null : highlightIndex! + 1);
    final resolvedLabels =
        labels ?? (values.length == weekLabels.length ? weekLabels : null);
    final span = maxBarHeight - minBarHeight;

    final bars = <Widget>[];
    final labelWidgets = <Widget>[];

    for (var i = 0; i < values.length; i++) {
      final raw = values[i];
      final value = raw < 0 ? 0 : raw;
      final isFuture = futureStart != null && i >= futureStart;
      final isHighlight = highlightIndex == i;

      final Color color;
      if (isHighlight) {
        color = activeColor;
      } else if (isFuture) {
        color = emptyColor;
      } else {
        color = value > 0 ? pastColor : emptyColor;
      }

      final double height;
      if (isFuture || effectiveMax <= 0) {
        height = minBarHeight;
      } else {
        height = minBarHeight + (value / effectiveMax) * span;
      }

      bars.add(
        Container(
          width: barWidth,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(barRadius),
          ),
        ),
      );

      if (resolvedLabels != null && i < resolvedLabels.length) {
        labelWidgets.add(
          SizedBox(
            width: barWidth,
            child: Text(
              resolvedLabels[i],
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: labelSize,
                fontWeight:
                    isHighlight ? AppFontWeight.bold : AppFontWeight.medium,
                color: isHighlight ? highlightLabelColor : labelColor,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: bars,
        ),
        if (showLabels && labelWidgets.isNotEmpty) ...[
          SizedBox(height: labelGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labelWidgets,
          ),
        ],
      ],
    );
  }
}
