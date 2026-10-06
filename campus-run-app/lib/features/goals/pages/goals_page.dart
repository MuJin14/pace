import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../data/models/goal.dart';
import '../../../data/repositories/goal_repository.dart';
import '../providers/goal_provider.dart';

/// 运动目标：列表 + 新建 + 取消。
///
/// 三态：加载中（可下拉刷新）/ 错误（可重试）/ 空态（召唤语 + 可点动作）。
class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('运动目标')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreate(context, ref),
        tooltip: '新建目标',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(goalListProvider),
        child: async.when(
          loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
          error: (err, _) => ScrollableCenter(
            child: ErrorState(
              message: err is ApiException ? err.message : '目标加载失败，请稍后重试',
              onRetry: () => ref.invalidate(goalListProvider),
            ),
          ),
          data: (goals) {
            if (goals.isEmpty) {
              return ScrollableCenter(
                child: EmptyState(
                  icon: Icons.flag_outlined,
                  title: '还没有运动目标',
                  subtitle: '设定一个目标，让每一次跑步都有方向',
                  actionLabel: '设定第一个目标',
                  onAction: () => _showCreate(context, ref),
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageWide,
                AppSpacing.smLg,
                AppSpacing.pageWide,
                96, // 给悬浮按钮留出空间
              ),
              children: [
                const AppSectionTitle(title: '我的目标'),
                const SizedBox(height: AppSpacing.smLg),
                for (final goal in goals) ...[
                  _GoalCard(goal: goal),
                  const SizedBox(height: AppSpacing.smLg),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCreate(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GoalCreateSheet(),
    );
    ref.invalidate(goalListProvider);
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_periodLabel(goal.periodType)}目标 · ${Formatters.distance(goal.targetDistanceMeters)}',
                  style: const TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _StatusTag(status: goal.status),
            ],
          ),
          const SizedBox(height: AppSpacing.gap14),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: goal.progress,
              minHeight: 10,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              color: goal.status == 1 ? AppColors.gold : AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.smLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Formatters.distance(goal.currentDistanceMeters)} / ${Formatters.distance(goal.targetDistanceMeters)}',
                style: const TextStyle(
                  fontSize: AppFontSize.caption,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${(goal.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (goal.isActive) ...[
            const SizedBox(height: AppSpacing.smLg),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _cancel(context, ref, goal),
                child: const Text(
                  '取消目标',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _periodLabel(String type) {
    switch (type) {
      case 'monthly':
        return '月度';
      case 'custom':
        return '自定义';
      default:
        return '周度';
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Goal goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消目标'),
        content: const Text('确定取消这个进行中的目标吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('取消目标')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(goalRepositoryProvider).cancel(goal.id);
      ref.invalidate(goalListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已取消该目标')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final int status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      1 => ('已完成', AppColors.gold),
      2 => ('已过期', AppColors.textSecondary),
      3 => ('已取消', AppColors.textHint),
      _ => ('进行中', AppColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap10, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: AppFontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _GoalCreateSheet extends ConsumerStatefulWidget {
  const _GoalCreateSheet();

  @override
  ConsumerState<_GoalCreateSheet> createState() => _GoalCreateSheetState();
}

class _GoalCreateSheetState extends ConsumerState<_GoalCreateSheet> {
  String _periodType = 'weekly';
  final _distanceController = TextEditingController();
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _submitting = false;

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _customStart != null && _customEnd != null
        ? DateTimeRange(start: _customStart!, end: _customEnd!)
        : DateTimeRange(start: now, end: now.add(const Duration(days: 6)));
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      helpText: '选择目标周期',
    );
    if (range != null) {
      setState(() {
        _customStart = range.start;
        _customEnd = range.end;
      });
    }
  }

  Future<void> _submit() async {
    final km = double.tryParse(_distanceController.text.trim());
    if (km == null || km <= 0) {
      _show('请输入大于 0 的目标距离（公里）');
      return;
    }
    // 自定义目标才需客户端指定起止日期；周 / 月周期由服务端按当前周期推导。
    final isCustom = _periodType == 'custom';
    if (isCustom && (_customStart == null || _customEnd == null)) {
      _show('请先选择自定义目标的开始与结束日期');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(goalRepositoryProvider).create(
            periodType: _periodType,
            targetDistanceMeters: (km * 1000).round(),
            // weekly / monthly 不再强传日期，交由服务端推导（契约见 task-2）。
            startDate: isCustom ? _fmt(_customStart!) : null,
            endDate: isCustom ? _fmt(_customEnd!) : null,
          );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _show(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '新建目标',
            style: TextStyle(
              fontSize: AppFontSize.headline,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.pageWide),
          const Text(
            '目标周期',
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: AppFontWeight.medium,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.gap10),
          Row(
            children: [
              _periodChip('weekly', '周目标'),
              const SizedBox(width: AppSpacing.sm),
              _periodChip('monthly', '月目标'),
              const SizedBox(width: AppSpacing.sm),
              _periodChip('custom', '自定义'),
            ],
          ),
          if (_periodType == 'custom') ...[
            const SizedBox(height: AppSpacing.md),
            _DateRangeField(
              start: _customStart,
              end: _customEnd,
              onTap: _pickRange,
            ),
          ],
          const SizedBox(height: AppSpacing.pageWide),
          TextField(
            controller: _distanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '目标距离（公里）',
              prefixIcon: Icon(Icons.straighten, color: AppColors.textHint),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('创建目标'),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    return AppChip(
      label: label,
      selected: _periodType == value,
      onTap: () => setState(() => _periodType = value),
    );
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({required this.start, required this.end, required this.onTap});

  final DateTime? start;
  final DateTime? end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasRange = start != null && end != null;
    final label = hasRange ? '${_fmtDate(start!)} ~ ${_fmtDate(end!)}' : '选择日期范围';
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.gap14,
          ),
          child: Row(
            children: [
              const Icon(Icons.date_range, size: 20, color: AppColors.textHint),
              const SizedBox(width: AppSpacing.smLg),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    color: hasRange ? AppColors.textPrimary : AppColors.textHint,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
