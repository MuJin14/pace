import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/goal.dart';
import '../../../data/repositories/goal_repository.dart';
import '../providers/goal_provider.dart';

/// 运动目标：列表 + 新建 + 取消。
class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('运动目标')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreate(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is ApiException ? err.message : '加载失败',
          onRetry: () => ref.invalidate(goalListProvider),
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return const EmptyState(
              icon: Icons.flag_outlined,
              title: '还没有运动目标',
              subtitle: '设定一个目标，让运动更有方向',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(goalListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              itemCount: goals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _GoalCard(goal: goals[i]),
            ),
          );
        },
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_periodLabel(goal.periodType)}目标 · ${Formatters.distance(goal.targetDistanceMeters)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              _StatusTag(status: goal.status),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: goal.progress,
              minHeight: 10,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              color: goal.status == 1 ? AppColors.gold : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Formatters.distance(goal.currentDistanceMeters)} / ${Formatters.distance(goal.targetDistanceMeters)}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              Text(
                '${(goal.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),
          if (goal.isActive) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _cancel(context, ref, goal),
                child: const Text('取消目标', style: TextStyle(color: AppColors.danger)),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
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
  bool _submitting = false;

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final km = double.tryParse(_distanceController.text.trim());
    if (km == null || km <= 0) {
      _show('请输入有效的目标距离');
      return;
    }
    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      String? startDate;
      String? endDate;
      switch (_periodType) {
        case 'weekly':
          final monday = now.subtract(Duration(days: now.weekday - 1));
          startDate = _fmt(DateTime(monday.year, monday.month, monday.day));
          endDate = _fmt(DateTime(monday.year, monday.month, monday.day).add(const Duration(days: 6)));
          break;
        case 'monthly':
          startDate = _fmt(DateTime(now.year, now.month, 1));
          endDate = _fmt(DateTime(now.year, now.month + 1, 0));
          break;
      }
      await ref.read(goalRepositoryProvider).create(
            periodType: _periodType,
            targetDistanceMeters: (km * 1000).round(),
            startDate: startDate,
            endDate: endDate,
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
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('新建目标', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          const Text('目标周期', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: [
              _periodChip('weekly', '周目标'),
              const SizedBox(width: 8),
              _periodChip('monthly', '月目标'),
              const SizedBox(width: 8),
              _periodChip('custom', '自定义'),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _distanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '目标距离（公里）',
              prefixIcon: Icon(Icons.straighten, color: AppColors.textHint),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _submitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Text('创建目标'),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    final selected = _periodType == value;
    return Expanded(
      child: ChoiceChip(
        label: SizedBox(width: double.infinity, child: Text(label, textAlign: TextAlign.center)),
        selected: selected,
        onSelected: (_) => setState(() => _periodType = value),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.card,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        showCheckmark: false,
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
