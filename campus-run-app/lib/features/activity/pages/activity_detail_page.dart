import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_metric_text.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/error_state.dart';
import '../../../data/models/activity_detail.dart';
import '../providers/activity_detail_provider.dart';
import '../widgets/track_map.dart';

/// 运动记录详情：距离大数字 + 元信息 + 轨迹地图 + 三栏数据网格。
class ActivityDetailPage extends ConsumerWidget {
  const ActivityDetailPage({super.key, required this.activityId});

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activityDetailProvider(activityId));
    return Scaffold(
      appBar: AppBar(title: const Text('运动详情')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(
          message: err is ApiException ? err.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(activityDetailProvider(activityId)),
        ),
        data: (detail) => _DetailBody(
          detail: detail,
          onEmptyTrackAction: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/activity');
            }
          },
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.onEmptyTrackAction});

  final ActivityDetail detail;
  final VoidCallback onEmptyTrackAction;

  @override
  Widget build(BuildContext context) {
    final color = detail.isRunning ? AppColors.run : AppColors.ride;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      children: [
        AppCard(
          child: Column(
            children: [
              _DistanceHeader(meters: detail.distanceMeters),
              const SizedBox(height: AppSpacing.md),
              _MetaRow(detail: detail, color: color),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppSectionTitle(title: '运动轨迹'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 200,
              child: TrackMap(
                track: detail.track,
                color: color,
                emptyText: '这次运动没有留下轨迹',
                emptyDescription: '下次跑起来，轨迹会显示在这里',
                emptyActionLabel: '返回运动记录',
                onEmptyAction: onEmptyTrackAction,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppSectionTitle(title: '运动数据'),
        const SizedBox(height: AppSpacing.sm),
        _StatsGrid(detail: detail),
      ],
    );
  }
}

class _DistanceHeader extends StatelessWidget {
  const _DistanceHeader({required this.meters});

  final int meters;

  @override
  Widget build(BuildContext context) {
    return AppMetricText(
      value: (meters / 1000).toStringAsFixed(2),
      label: '公里',
      valueSize: AppFontSize.metricLg,
      labelSize: AppFontSize.caption,
      labelColor: AppColors.textSecondary,
      labelGap: AppSpacing.xxs,
      color: AppColors.textPrimary,
      crossAxisAlignment: CrossAxisAlignment.center,
      textAlign: TextAlign.center,
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.detail, required this.color});

  final ActivityDetail detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = detail.isRunning ? '跑步' : '骑行';
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  detail.isRunning
                      ? Icons.directions_run
                      : Icons.directions_bike,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    '$label · ${Formatters.dateTimeCn(detail.startTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.body,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (detail.invalid == 1)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Text(
                '无效',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: AppColors.onPrimary,
                  fontWeight: AppFontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.detail});

  final ActivityDetail detail;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              value: Formatters.duration(detail.durationSeconds),
              label: '时长',
            ),
          ),
          Expanded(
            child: _StatCell(
              value: Formatters.pace(detail.avgPace),
              label: '配速',
            ),
          ),
          Expanded(
            child: _StatCell(
              value: Formatters.calories(detail.calories),
              label: '消耗',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppMetricText(
      value: value,
      label: label,
      valueSize: AppFontSize.headline,
      valueWeight: AppFontWeight.medium,
      labelSize: AppFontSize.caption,
      labelColor: AppColors.textSecondary,
      labelGap: AppSpacing.xs,
      color: AppColors.textPrimary,
      crossAxisAlignment: CrossAxisAlignment.center,
      textAlign: TextAlign.center,
    );
  }
}
