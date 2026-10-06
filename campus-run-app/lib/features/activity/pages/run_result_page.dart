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
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/activity_detail.dart';
import '../providers/activity_detail_provider.dart';
import '../widgets/track_map.dart';

/// 运动完成结果页：轨迹地图 + 距离/时长/配速 + 返回首页。
class RunResultPage extends ConsumerWidget {
  const RunResultPage({super.key, required this.activityId});

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activityDetailProvider(activityId));
    return Scaffold(
      appBar: AppBar(title: const Text('运动完成')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(
          message: err is ApiException ? err.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(activityDetailProvider(activityId)),
        ),
        data: (detail) => _ResultBody(detail: detail),
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.detail});

  final ActivityDetail detail;

  @override
  Widget build(BuildContext context) {
    final color = detail.isRunning ? AppColors.run : AppColors.ride;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              AppSpacing.md,
            ),
            children: [
              const AppSectionTitle(title: '本次轨迹'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    height: 180,
                    child: TrackMap(
                      track: detail.track,
                      color: color,
                      emptyText: '这次运动没有留下轨迹',
                      emptyDescription: '这次运动没有记录到 GPS 轨迹',
                      emptyActionLabel: '返回首页',
                      onEmptyAction: () => context.go('/home'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const AppSectionTitle(title: '运动数据'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  children: [
                    AppMetricText(
                      value: Formatters.distance(detail.distanceMeters),
                      valueSize: AppFontSize.metricXl,
                      color: color,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppMetricText(
                      value: Formatters.duration(detail.durationSeconds),
                      valueSize: AppFontSize.display,
                      color: AppColors.textPrimary,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '配速 ${Formatters.pace(detail.avgPace)}',
                      style: const TextStyle(
                        fontSize: AppFontSize.body,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          child: PrimaryButton(
            label: '返回首页',
            onPressed: () => context.go('/home'),
          ),
        ),
      ],
    );
  }
}
