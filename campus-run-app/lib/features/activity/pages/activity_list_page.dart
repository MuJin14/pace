import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
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
                  child: _ErrorView(
                    message: err is ApiException ? err.message : '加载失败，请稍后重试',
                    onRetry: () => ref.invalidate(activityListProvider),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const ScrollableCenter(
                      child: EmptyState(
                        icon: Icons.directions_run,
                        title: '还没有运动记录',
                        subtitle: '去首页开始你的第一次跑步或骑行吧',
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: list.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == list.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: loadingMore
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Text('上拉加载更多', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          _chip(context, null, '全部'),
          const SizedBox(width: 8),
          _chip(context, 1, '跑步'),
          const SizedBox(width: 8),
          _chip(context, 2, '骑行'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, int? value, String label) {
    final selected = this.selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.card,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      showCheckmark: false,
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
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(item.isRunning ? Icons.directions_run : Icons.directions_bike, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.isRunning ? '跑步' : '骑行',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 8),
                        if (item.avgPace != null)
                          Text(
                            '配速 ${Formatters.pace(item.avgPace)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Formatters.dateTime(item.startTime),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.distance(item.distanceMeters),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Formatters.duration(item.durationSeconds),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
