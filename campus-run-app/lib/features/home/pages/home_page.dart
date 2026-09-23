import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/activity_summary.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/user.dart';
import '../../activity/providers/activity_list_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../goals/providers/goal_provider.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';

/// 首页工作台：问候 + 快捷开跑 + 今日统计 + 目标进度 + 近期记录。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(activityListProvider);
            ref.invalidate(goalListProvider);
            ref.invalidate(myRankProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _GreetingHeader(user: user),
              const SizedBox(height: 20),
              const _QuickStartCard(),
              const SizedBox(height: 24),
              const _TodayStats(),
              const SizedBox(height: 24),
              const _GoalSection(),
              const SizedBox(height: 24),
              const _RecentSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final nickname = user?.nickname ?? '';
    final uniqueId = user?.uniqueId ?? '';
    return Row(
      children: [
        UserAvatar(nickname: nickname, avatarUrl: user?.avatarUrl, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '你好，$nickname',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (uniqueId.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    uniqueId,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard();

  void _toast(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('轨迹记录功能即将上线，敬请期待')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '今天想动一动吗？',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '开始记录你的跑步或骑行轨迹',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StartButton(
                  icon: Icons.directions_run,
                  label: '开始跑步',
                  onTap: () => _toast(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StartButton(
                  icon: Icons.directions_bike,
                  label: '开始骑行',
                  onTap: () => _toast(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayStats extends ConsumerWidget {
  const _TodayStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(myRankProvider(('daily', 1))).value;
    final ride = ref.watch(myRankProvider(('daily', 2))).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '今日运动'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.directions_run,
                color: AppColors.run,
                label: '跑步',
                value: Formatters.distance(run?.distanceMeters ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.directions_bike,
                color: AppColors.ride,
                label: '骑行',
                value: Formatters.distance(ride?.distanceMeters ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.emoji_events,
                color: AppColors.gold,
                label: '跑步排名',
                value: run?.rank != null ? '第${run!.rank}名' : '—',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _GoalSection extends ConsumerWidget {
  const _GoalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalListProvider).value;
    final active = goals?.where((g) => g.isActive).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '运动目标',
          action: GestureDetector(
            onTap: () => context.push('/goals'),
            child: const Text(
              '查看全部',
              style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (active == null)
          _EmptyGoalCard(onTap: () => context.push('/goals'))
        else
          _GoalCard(goal: active),
      ],
    );
  }
}

class _EmptyGoalCard extends StatelessWidget {
  const _EmptyGoalCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flag_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              '还没有进行中的目标，设置一个周目标吧',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textHint),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final target = goal.targetDistanceMeters;
    final current = goal.currentDistanceMeters;
    final progress = goal.progress;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '周目标 · ${Formatters.distance(target)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '已完成 ${Formatters.distance(current)}，还差 ${Formatters.distance((target - current).clamp(0, target))}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(activityListProvider).value ?? const <ActivitySummary>[];
    final recent = items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '近期运动',
          action: GestureDetector(
            onTap: () => context.go('/activity'),
            child: const Text(
              '查看全部',
              style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text('还没有运动记录，快去跑一跑吧', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ),
          )
        else
          ...recent.map((e) => _RecentItem(item: e)),
      ],
    );
  }
}

class _RecentItem extends StatelessWidget {
  const _RecentItem({required this.item});

  final ActivitySummary item;

  @override
  Widget build(BuildContext context) {
    final color = item.isRunning ? AppColors.run : AppColors.ride;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(item.isRunning ? Icons.directions_run : Icons.directions_bike, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.isRunning ? '跑步' : '骑行',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                Formatters.duration(item.durationSeconds),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        if (action != null) action!,
      ],
    );
  }
}
