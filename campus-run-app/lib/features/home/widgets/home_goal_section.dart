import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../data/models/goal.dart';

/// 设计稿 §2：进度条高 8（属尺寸而非间距，用语义常量命名）。
const double _kBarHeight = 8;

/// 首页「运动目标」区块（设计稿 §1：区块高度 118）。
///
/// - 有进行中的目标 → [_GoalCard]：周期 + 目标距离 + 进度条 + 百分比（16/700 橙）
/// - 无进行中的目标 → [_EmptyGoalCard]：召唤语 + 橙色胶囊「设置目标」（设计稿 §3）
///
/// 跳转由页面注入，widget 内部不做 `context.push`：
/// - [onSetGoal]：必填，空态「设置目标」动作
/// - [onSeeAll]：可选，标题右侧「查看全部」（为 null 时隐藏）
class HomeGoalSection extends StatelessWidget {
  const HomeGoalSection({
    super.key,
    required this.goals,
    required this.onSetGoal,
    this.onSeeAll,
  });

  final List<Goal> goals;
  final VoidCallback onSetGoal;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final goal = _homeActiveGoal(goals);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionTitle(title: '运动目标', onSeeAll: onSeeAll),
        const SizedBox(height: AppSpacing.smLg),
        if (goal == null)
          _EmptyGoalCard(onSetGoal: onSetGoal)
        else
          _GoalCard(goal: goal),
      ],
    );
  }
}

/// 进行中目标卡：主行（周期 + 目标距离 / 百分比）+ 说明 + 橙渐变进度条。
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final remaining = (goal.targetDistanceMeters - goal.currentDistanceMeters)
        .clamp(0, goal.targetDistanceMeters);
    final days = _homeDaysLeft(goal.endDate);
    final subtitle =
        '本周还差 ${Formatters.distance(remaining)}'
        '${days != null ? ' · 还剩 $days 天' : ''}';

    return AppDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${_homePeriodLabel(goal)} '
                  '${Formatters.distance(goal.targetDistanceMeters)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.labelLg,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(goal.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.accentHot,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: AppFontSize.hint,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.smLg),
          _GradientProgressBar(value: goal.progress),
        ],
      ),
    );
  }
}

/// 进度条：高 8、圆角 999、轨道 #F5EDE6、填充橙渐变（终点 #FF7A2E）——设计稿 §2。
class _GradientProgressBar extends StatelessWidget {
  const _GradientProgressBar({required this.value});

  /// 0.0 ~ 1.0，超出范围会被裁剪。
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kBarHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.goalTrack,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.heroGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 无进行中目标：召唤语 + 橙色胶囊「设置目标」（设计稿 §3）。
class _EmptyGoalCard extends StatelessWidget {
  const _EmptyGoalCard({required this.onSetGoal});

  final VoidCallback onSetGoal;

  @override
  Widget build(BuildContext context) {
    return AppDashboardCard(
      child: AppEmptyHint(
        layout: AppEmptyHintLayout.row,
        title: '还没有进行中的目标',
        titleSize: AppFontSize.labelLg,
        titleWeight: AppFontWeight.regular,
        titleColor: AppColors.textSecondary,
        actionLabel: '设置目标',
        onAction: onSetGoal,
      ),
    );
  }
}

// ── 自包含工具（复制自 home_page.dart，避免 import 页面文件形成环） ──
DateTime _homeDayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// 进行中的目标（status == 0），没有则返回 null。
Goal? _homeActiveGoal(List<Goal> goals) {
  for (final g in goals) {
    if (g.isActive) return g;
  }
  return null;
}

/// 距目标结束日期剩余天数；解析失败返回 null，已过期返回 0。
int? _homeDaysLeft(String? endDate) {
  final d = DateTime.tryParse(endDate ?? '');
  if (d == null) return null;
  final diff = _homeDayOf(d).difference(_homeDayOf(DateTime.now())).inDays;
  return diff < 0 ? 0 : diff;
}

String _homePeriodLabel(Goal g) => switch (g.periodType) {
  'monthly' => '每月',
  'custom' => '目标',
  _ => '每周',
};
