import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/account_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/activity_summary.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/my_rank.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../activity/pages/start_sheet.dart';
import '../../activity/providers/activity_list_provider.dart';
import '../../goals/providers/goal_provider.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../widgets/home_activity_list.dart';
import '../widgets/home_goal_section.dart';
import '../widgets/home_hero.dart';
import '../widgets/home_today_stats.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/home_weekly_volume.dart';

const String _kWeather = '晴 18°'; // 占位：后端暂无天气接口
const List<String> _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 设计稿空态占位：无进行中目标时，本周跑量右侧展示的默认周目标（不写 0）。
const int _kDefaultWeekGoalMeters = 20000;

// ── 日期 / 聚合工具 ─────────────────────────────────────────────
DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _parseDay(String s) {
  final dt = DateTime.tryParse(s);
  return dt == null ? null : _dayOf(dt);
}

bool _isRun(ActivitySummary a) => a.type == 1;

DateTime _thisMonday() {
  final now = _dayOf(DateTime.now());
  return now.subtract(Duration(days: now.weekday - 1));
}

bool _inWeek(DateTime day, DateTime monday) =>
    !day.isBefore(monday) && !day.isAfter(monday.add(const Duration(days: 6)));

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _dateLabel(DateTime d) => '${_weekdays[d.weekday - 1]} · ${d.month}月${d.day}日';

String _km(int meters) => (meters / 1000).toStringAsFixed(1);

String _signedKm(int meters) {
  final v = meters / 1000.0;
  final s = v.toStringAsFixed(1);
  return v >= 0 ? '+$s km' : '$s km';
}

List<ActivitySummary> _onDay(List<ActivitySummary> items, DateTime day) => items
    .where((a) => _parseDay(a.startTime) == day)
    .toList();

int _sumDistance(Iterable<ActivitySummary> items) =>
    items.fold(0, (s, a) => s + a.distanceMeters);

int _sumDuration(Iterable<ActivitySummary> items) =>
    items.fold(0, (s, a) => s + a.durationSeconds);

int? _paceOf(int durationSeconds, int distanceMeters) =>
    distanceMeters > 0 ? (durationSeconds * 1000 / distanceMeters).round() : null;

int _dayRunDistance(List<ActivitySummary> items, DateTime day) {
  int sum = 0;
  for (final a in items) {
    if (_isRun(a) && _parseDay(a.startTime) == day) sum += a.distanceMeters;
  }
  return sum;
}

int _weekRunDistance(List<ActivitySummary> items, DateTime monday) {
  int sum = 0;
  for (final a in items) {
    final d = _parseDay(a.startTime);
    if (d != null && _isRun(a) && _inWeek(d, monday)) sum += a.distanceMeters;
  }
  return sum;
}

int _weekRunCount(List<ActivitySummary> items, DateTime monday) => items
    .where((a) {
      final d = _parseDay(a.startTime);
      return d != null && _isRun(a) && _inWeek(d, monday);
    })
    .length;

Goal? _activeGoal(List<Goal> goals) {
  for (final g in goals) {
    if (g.isActive) return g;
  }
  return null;
}

/// 目标距离文案：整数 km 不带小数（对齐设计稿「周目标 20 km」）。
String _goalKm(int meters) {
  final km = meters / 1000;
  final text = km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
  return '$text km';
}

/// 首页「开始跑步」入口：先弹运动类型选择，再跳转记录页。
Future<void> _startRun(BuildContext context) async {
  final type = await showStartSheet(context);
  if (type != null && context.mounted) {
    context.push('/start-run', extra: type);
  }
}

/// 上周同类型排名，仅用于「上升 X 位」。私有数据，随账号变化。
final _lastWeekRankProvider =
    FutureProvider.autoDispose.family<MyRank, int>((ref, type) async {
  // 不 watchUserId 的话，切账号后首页会显示上一个账号的名次。
  if (ref.watchUserId() == null) {
    return const MyRank(rank: null, distanceMeters: 0, total: 0);
  }
  final lastMonday = _thisMonday().subtract(const Duration(days: 7));
  return ref
      .read(leaderboardRepositoryProvider)
      .myRank(scope: 'weekly', type: type, period: _fmtDate(lastMonday));
});

/// 首页工作台：顶栏 + 今日目标 + 今日运动 + 本周跑量 + 校园榜 + 目标 + 近期记录。
///
/// 页面只做数据聚合与区块编排，视觉细节全部下沉到 `widgets/home_*.dart`。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities =
        ref.watch(activityListProvider).value ?? const <ActivitySummary>[];
    final goals = ref.watch(goalListProvider).value ?? const <Goal>[];

    // 今日聚合
    final today = _dayOf(DateTime.now());
    final monday = _thisMonday();
    final todays = _onDay(activities, today);
    final todayDistance = _sumDistance(todays);
    final todayDuration = _sumDuration(todays);
    final todayPace = _paceOf(todayDuration, todayDistance);
    final yesterdayDistance =
        _sumDistance(_onDay(activities, today.subtract(const Duration(days: 1))));
    final delta = todayDistance - yesterdayDistance;

    // 目标聚合
    final goal = _activeGoal(goals);
    final dailyTarget = goal == null ? 0.0 : goal.targetDistanceMeters / 7.0;
    final hasTarget = dailyTarget > 0;
    final progress =
        hasTarget ? (todayDistance / dailyTarget).clamp(0.0, 1.0) : 0.0;
    final weekRunCount = _weekRunCount(activities, monday);

    // 本周聚合
    final weekValues = List<int>.generate(
      7,
      (i) => _dayRunDistance(activities, monday.add(Duration(days: i))),
    );
    final weekTotal = weekValues.fold(0, (a, b) => a + b);
    final lastWeek =
        _weekRunDistance(activities, monday.subtract(const Duration(days: 7)));
    final goalText =
        '周目标 ${_goalKm(goal?.targetDistanceMeters ?? _kDefaultWeekGoalMeters)}';

    // 校园榜聚合（上周排名 provider 仅本文件可见，故在页面取值后下传）
    final thisWeekRank = ref.watch(myRankProvider(('weekly', 1))).value;
    final lastWeekRank = ref.watch(_lastWeekRankProvider(1)).value;

    // 空态预算（设计稿 §3：同屏最多保留 2 处空态，数据缺失整块隐藏优于显示 0）。
    // 本页上半已占用：Hero 召唤型空态 + 今日运动说明型空态，合计最多 2 处；
    // 达到预算时整块隐藏下半的「运动目标 / 近期运动」空态（有真实数据时照常展示）。
    final emptyStateCount = (todayDistance > 0 ? 0 : 1) +
        (todayDistance > 0 || todayDuration > 0 ? 0 : 1);
    final showGoalBlock = goal != null || emptyStateCount < 2;
    final showRecentBlock = activities.isNotEmpty || emptyStateCount < 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(activityListProvider);
            ref.invalidate(goalListProvider);
            ref.invalidate(myRankProvider(('weekly', 1)));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageWide,
              AppSpacing.smLg,
              AppSpacing.pageWide,
              AppSpacing.lg,
            ),
            children: [
              HomeTopBar(dateText: '${_dateLabel(DateTime.now())} · $_kWeather'),
              const SizedBox(height: AppSpacing.block),
              if (todayDistance > 0)
                HomeHeroGoalCard(
                  distanceText: _km(todayDistance),
                  targetText: hasTarget ? _km(dailyTarget.round()) : null,
                  remainingText: hasTarget
                      ? _km((dailyTarget - todayDistance)
                          .clamp(0, dailyTarget)
                          .round())
                      : null,
                  weekRunCount: weekRunCount,
                  progress: progress,
                  onStart: () => _startRun(context),
                )
              else
                HomeEmptyHero(onStart: () => _startRun(context)),
              const SizedBox(height: AppSpacing.block),
              HomeTodayStatStrip(
                hasData: todayDistance > 0 || todayDuration > 0,
                distanceText: _km(todayDistance),
                durationText: Formatters.duration(todayDuration),
                paceText: Formatters.pace(todayPace),
                showDelta: yesterdayDistance > 0,
                deltaPositive: delta >= 0,
                deltaText: _signedKm(delta),
                onStartRun: () => _startRun(context),
              ),
              const SizedBox(height: AppSpacing.block),
              HomeWeeklyVolumeCard(
                values: weekValues,
                todayIndex: today.difference(monday).inDays,
                totalText: weekTotal > 0 ? _km(weekTotal) : null,
                goalText: goalText,
                progressText:
                    goal != null ? '完成 ${(goal.progress * 100).round()}%' : null,
                lastWeekText:
                    lastWeek > 0 ? '较上周 ${_signedKm(weekTotal - lastWeek)}' : null,
                onStartRun: () => _startRun(context),
              ),
              const SizedBox(height: AppSpacing.block),
              HomeCampusRankRow(
                rank: thisWeekRank?.rank,
                total: thisWeekRank?.total ?? 0,
                lastWeekRank: lastWeekRank?.rank,
              ),
              if (showGoalBlock) ...[
                const SizedBox(height: AppSpacing.block),
                HomeGoalSection(
                  goals: goals,
                  onSetGoal: () => context.push('/goals'),
                  onSeeAll: () => context.push('/goals'),
                ),
              ],
              if (showRecentBlock) ...[
                const SizedBox(height: AppSpacing.block),
                HomeActivityList(
                  items: activities,
                  onStartRun: () => _startRun(context),
                  onSeeAll: () => context.push('/activity'),
                  onItemTap: (item) => context.push('/activity/${item.activityId}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 运动目标 / 近期运动 ─────────────────────────────────────────
// 两块已下沉为独立组件：
//   widgets/home_goal_section.dart  → HomeGoalSection
//   widgets/home_activity_list.dart → HomeActivityList
// 页面只负责「是否渲染该区块」（空态预算）与跳转回调注入。
