import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../data/models/activity_summary.dart';
import '../providers/activity_list_provider.dart';

/// 运动记录列表：类型筛选 + 卡片列表 + 下拉刷新 + 上拉加载。
class ActivityListPage extends ConsumerStatefulWidget {
  const ActivityListPage({super.key});

  @override
  ConsumerState<ActivityListPage> createState() => _ActivityListPageState();
}

class _ActivityListPageState extends ConsumerState<ActivityListPage> {
  int? _type;

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(activityListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('运动记录')),
      body: Column(
        children: [
          _FilterBar(selected: _type, onChanged: _onFilter),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(activityListProvider.notifier).refresh(),
              child: listAsync.when(
                loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
                error: (err, _) => ScrollableCenter(
                  child: ErrorState(
                    message: err is ApiException ? err.message : '加载失败，请稍后重试',
                    onRetry: () => ref.invalidate(activityListProvider),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return ScrollableCenter(
                      child: EmptyState(
                        icon: Icons.directions_run,
                        title: '还没有运动记录',
                        subtitle: '去跑一跑，留下你的第一条轨迹',
                        actionLabel: '去跑步',
                        onAction: () => context.push('/start-run'),
                      ),
                    );
                  }
                  return _buildList(list);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onFilter(int? type) {
    setState(() => _type = type);
    ref.read(activityListProvider.notifier).setType(type);
  }

  Widget _buildList(List<ActivitySummary> list) {
    final loadingMore = ref.watch(activityLoadingMoreProvider);
    final hasMore = ref.read(activityListProvider.notifier).hasMore;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
          ref.read(activityListProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        itemCount: list.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == list.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: loadingMore
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text(
                        '上拉加载更多',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: AppColors.textHint,
                        ),
                      ),
              ),
            );
          }
          final item = list[index];
          return _ActivityCard(
            item: item,
            onTap: () => context.push('/activity/${item.activityId}'),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          _chip(null, '全部'),
          const SizedBox(width: AppSpacing.sm),
          _chip(1, '跑步'),
          const SizedBox(width: AppSpacing.sm),
          _chip(2, '骑行'),
        ],
      ),
    );
  }

  Widget _chip(int? value, String label) {
    return AppChip(
      label: label,
      selected: selected == value,
      onTap: () => onChanged(value),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item, required this.onTap});

  final ActivitySummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.isRunning ? AppColors.run : AppColors.ride;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.isRunning ? Icons.directions_run : Icons.directions_bike,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.isRunning ? '跑步' : '骑行',
                      style: const TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (item.avgPace != null)
                      Text(
                        '配速 ${Formatters.pace(item.avgPace)}',
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Formatters.dateTime(item.startTime),
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.distance(item.distanceMeters),
                style: const TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                Formatters.duration(item.durationSeconds),
                style: const TextStyle(
                  fontSize: AppFontSize.caption,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
        ],
      ),
    );
  }
}
