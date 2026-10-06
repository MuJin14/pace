import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_mini_bar_chart.dart';
import '../../../core/widgets/app_text_action.dart';

/// 本周跑量卡：7 柱迷你柱状图 + 环比 + 周目标进度。
///
/// 柱状图复用 [AppMiniBarChart]（柱宽 24、圆角 6、今日热橙、已跑 #FFC79A、
/// 未跑 / 未来 #F2EDE8、日期标签 9.6）。无数据时保留 7 根空柱维持结构，
/// 右侧改显「周目标 20 km」，脚注给「去跑步」文字动作，不写 0。
class HomeWeeklyVolumeCard extends StatelessWidget {
  const HomeWeeklyVolumeCard({
    super.key,
    required this.values,
    required this.todayIndex,
    required this.totalText,
    required this.goalText,
    required this.progressText,
    required this.lastWeekText,
    required this.onStartRun,
  });

  /// 周一至周日每天的跑步距离（米）。
  final List<int> values;

  /// 今天在本周中的下标（0 = 周一）；其后自动视为未来日。
  final int todayIndex;

  /// 本周总距离文案（km，1 位小数）；无数据时为 null → 右侧改显 [goalText]。
  final String? totalText;

  /// 周目标文案（如「周目标 20 km」）。
  final String goalText;

  /// 目标完成度文案（如「完成 62%」）；无目标时为 null → 脚注改显「去跑步」。
  final String? progressText;

  /// 较上周文案；上周无数据时为 null。
  final String? lastWeekText;

  /// 脚注「去跑步」动作。
  final VoidCallback onStartRun;

  @override
  Widget build(BuildContext context) {
    final total = totalText;
    final progress = progressText;
    final lastWeek = lastWeekText;

    return AppDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '本周跑量',
                style: TextStyle(
                  fontSize: AppFontSize.subtitle,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                total != null ? '$total km' : goalText,
                style: const TextStyle(
                  fontSize: AppFontSize.subtitle,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.accentHot,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap14),
          AppMiniBarChart(values: values, highlightIndex: todayIndex),
          const SizedBox(height: AppSpacing.gap14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (lastWeek != null)
                Text(
                  lastWeek,
                  style: const TextStyle(
                    fontSize: AppFontSize.tiny,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.deltaUp,
                  ),
                )
              else
                const SizedBox.shrink(),
              if (progress != null)
                Text(
                  '$goalText · $progress',
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                AppTextAction(
                  label: '去跑步',
                  onTap: onStartRun,
                  fontSize: AppFontSize.caption,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
