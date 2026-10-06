import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_delta_chip.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_metric_text.dart';
import '../../../core/widgets/app_text_action.dart';

/// 三栏分隔线（设计稿 §2：1×32 #F0E8E0）。
const double _cellDividerWidth = 1;
const double _cellDividerHeight = 32;

/// 校园榜行内尺寸（设计稿 §2：图标底 40 圆角 12、金杯 20、右箭头 18）。
const double _rankIconSize = 20;
const double _chevronSize = 18;

/// 今日运动三栏卡：标题 + 较昨日环比 chip + 距离 / 时长 / 配速。
///
/// 白卡圆角 16 + 极轻阴影（[AppDashboardCard]）、标题 [AppFontSize.subtitle]、
/// chip [AppDeltaChip]、三栏数字 [AppFontSize.metric] + 标签 [AppFontSize.hint]。
/// 无数据时为说明型空态（圆形图标 + 14/700「今日还没有数据」+ 一行说明 + 去跑步动作），
/// 不出现 0 与破折号。
class HomeTodayStatStrip extends StatelessWidget {
  const HomeTodayStatStrip({
    super.key,
    required this.hasData,
    required this.distanceText,
    required this.durationText,
    required this.paceText,
    required this.showDelta,
    required this.deltaPositive,
    required this.deltaText,
    required this.onStartRun,
  });

  /// 今日是否有距离或时长数据。
  final bool hasData;

  final String distanceText;
  final String durationText;
  final String paceText;

  /// 昨日有数据时才展示环比 chip。
  final bool showDelta;
  final bool deltaPositive;
  final String deltaText;

  /// 空态动作「去跑步」。
  final VoidCallback onStartRun;

  @override
  Widget build(BuildContext context) {
    return AppDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '今日运动',
                style: TextStyle(
                  fontSize: AppFontSize.subtitle,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (showDelta) AppDeltaChip(text: deltaText, positive: deltaPositive),
            ],
          ),
          const SizedBox(height: AppSpacing.gap14),
          if (!hasData)
            AppEmptyHint(
              layout: AppEmptyHintLayout.row,
              icon: Icons.insights_outlined,
              iconSize: AppSpacing.pageWide,
              iconBoxSize: AppSpacing.xxl,
              iconColor: AppColors.textHint,
              iconBackground: AppColors.surface,
              title: '今日还没有数据',
              titleSize: AppFontSize.body,
              description: '完成第一次运动后，这里会显示距离、时长与配速',
              descriptionSize: AppFontSize.caption,
              action: AppTextAction(
                label: '去跑步',
                onTap: onStartRun,
                fontSize: AppFontSize.caption,
              ),
            )
          else
            Row(
              children: [
                _StatCell(value: distanceText, label: '距离 (km)'),
                const _CellDivider(),
                _StatCell(value: durationText, label: '时长 (分:秒)'),
                const _CellDivider(),
                _StatCell(value: paceText, label: '配速 (/km)'),
              ],
            ),
        ],
      ),
    );
  }
}

/// 单栏数字 + 标签（数字 23.6/700 行高 1.0、标签 11.6/400）。
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(child: AppMetricText(value: value, label: label));
  }
}

/// 1×32 分隔线。
class _CellDivider extends StatelessWidget {
  const _CellDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _cellDividerWidth,
      height: _cellDividerHeight,
      color: AppColors.borderLight,
    );
  }
}

/// 校园榜单行卡：金杯 40 圆角 12 图标底 + 标题 + 转化文案，整行可点跳 `/leaderboard`。
///
/// 未上榜时不显示名次数字与占位破折号，只给「跑一次即可上榜，争夺校园第一」。
class HomeCampusRankRow extends StatelessWidget {
  const HomeCampusRankRow({
    super.key,
    required this.rank,
    required this.total,
    required this.lastWeekRank,
  });

  /// 本周跑步榜名次；null = 未上榜。
  final int? rank;

  /// 榜内总人数。
  final int total;

  /// 上周跑步榜名次，用于「上升 / 下降 X 位」。
  final int? lastWeekRank;

  @override
  Widget build(BuildContext context) {
    // 提升为局部变量：Dart 不对公开字段做类型提升。
    final currentRank = rank;
    final previousRank = lastWeekRank;
    final percentile = (currentRank != null && total > 1)
        ? ((total - currentRank) / total * 100).round()
        : null;

    final parts = <String>[];
    if (currentRank != null) {
      if (percentile != null) parts.add('超越 $percentile% 的跑者');
      if (previousRank != null) {
        final delta = previousRank - currentRank;
        if (delta > 0) {
          parts.add('上升 $delta 位');
        } else if (delta < 0) {
          parts.add('下降 ${-delta} 位');
        } else {
          parts.add('排名持平');
        }
      }
    }

    return AppDashboardCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gap14,
        vertical: AppSpacing.md,
      ),
      onTap: () => context.push('/leaderboard'),
      child: Row(
        children: [
          Container(
            width: AppSpacing.xxl,
            height: AppSpacing.xxl,
            decoration: BoxDecoration(
              color: AppColors.iconBgWarm,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.emoji_events,
              size: _rankIconSize,
              color: AppColors.medal,
            ),
          ),
          const SizedBox(width: AppSpacing.smLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentRank != null ? '校园榜 第 $currentRank 名' : '校园榜',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  currentRank == null ? '跑一次即可上榜，争夺校园第一' : parts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: _chevronSize,
            color: AppColors.textHint,
          ),
        ],
      ),
    );
  }
}
