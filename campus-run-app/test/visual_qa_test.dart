// 视觉质量评估渲染工具（评估用，不属于常规断言测试）。
//
// 目的：用 golden 渲染把尽可能多的界面/组件/状态输出成 PNG，供人工逐张目视评审。
// 全部使用**假数据 + ProviderScope overrides**，不触碰网络与后端。
//
// 运行（工作目录 campus-run-app）：
//   $env:FLUTTER_SUPPRESS_ANALYTICS='true'; $env:FLUTTER_ALREADY_LOCKED='true'
//   flutter test --no-version-check --no-pub --update-goldens test/visual_qa_test.dart
//
// 输出：test/goldens/vq_*.png
//
// 约定：
// - 字体通过 FontLoader('Roboto') 加载 C:\Windows\Fonts\simhei.ttf，保证截图里中文可读；
// - 每个用例显式设置 view.physicalSize / devicePixelRatio，保证输出分辨率稳定；
// - 页面级用例用 ProviderScope(overrides: ...) 注入假数据，避免出现加载态/网络错误。
import 'dart:async';
import 'dart:io';

import 'package:campus_run_app/core/network/api_exception.dart';
import 'package:campus_run_app/core/theme/app_theme.dart';
import 'package:campus_run_app/core/widgets/app_widgets.dart';
import 'package:campus_run_app/features/home/widgets/home_activity_list.dart';
import 'package:campus_run_app/features/home/widgets/home_goal_section.dart';
import 'package:campus_run_app/features/home/widgets/home_hero.dart';
import 'package:campus_run_app/features/home/widgets/home_today_stats.dart';
import 'package:campus_run_app/features/home/widgets/home_top_bar.dart';
import 'package:campus_run_app/features/home/widgets/home_weekly_volume.dart';
import 'package:dio/dio.dart';
import 'package:campus_run_app/core/ws/global_ws_provider.dart';
import 'package:campus_run_app/core/ws/ws_message.dart';
import 'package:campus_run_app/data/models/activity_detail.dart';
import 'package:campus_run_app/data/models/activity_summary.dart';
import 'package:campus_run_app/data/models/badge.dart' as models;
import 'package:campus_run_app/data/models/chat_message.dart';
import 'package:campus_run_app/data/models/friend_item.dart';
import 'package:campus_run_app/data/models/friend_request.dart';
import 'package:campus_run_app/data/models/goal.dart';
import 'package:campus_run_app/data/models/leaderboard_entry.dart';
import 'package:campus_run_app/data/models/my_rank.dart';
import 'package:campus_run_app/data/models/page_response.dart';
import 'package:campus_run_app/data/models/user.dart';
import 'package:campus_run_app/data/models/user_badge.dart';
import 'package:campus_run_app/data/models/user_brief.dart';
import 'package:campus_run_app/data/repositories/leaderboard_repository.dart';
import 'package:campus_run_app/data/models/track_point.dart';
import 'package:campus_run_app/features/activity/pages/activity_detail_page.dart';
import 'package:campus_run_app/features/activity/pages/activity_list_page.dart';
import 'package:campus_run_app/features/activity/providers/activity_detail_provider.dart';
import 'package:campus_run_app/features/activity/providers/activity_list_provider.dart';
import 'package:campus_run_app/features/auth/pages/login_page.dart';
import 'package:campus_run_app/features/auth/pages/register_page.dart';
import 'package:campus_run_app/features/auth/providers/auth_provider.dart';
import 'package:campus_run_app/features/badges/pages/badges_page.dart';
import 'package:campus_run_app/features/badges/providers/badge_provider.dart';
import 'package:campus_run_app/features/friends/pages/chat_page.dart';
import 'package:campus_run_app/features/friends/pages/friends_page.dart';
import 'package:campus_run_app/features/friends/pages/friends_search_page.dart';
import 'package:campus_run_app/features/friends/providers/friend_provider.dart';
import 'package:campus_run_app/features/friends/providers/message_provider.dart';
import 'package:campus_run_app/features/goals/pages/goals_page.dart';
import 'package:campus_run_app/features/goals/providers/goal_provider.dart';
import 'package:campus_run_app/features/home/pages/home_page.dart';
import 'package:campus_run_app/features/leaderboard/pages/leaderboard_page.dart';
import 'package:campus_run_app/features/leaderboard/providers/leaderboard_provider.dart';
import 'package:campus_run_app/features/notifications/pages/notifications_page.dart';
import 'package:campus_run_app/features/profile/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

// ───────────────────────────── 基础设施 ─────────────────────────────

/// 加载系统中文字体，让截图里的中文可读。
Future<void> _loadCjkFont() async {
  for (final path in [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      return;
    }
  }
}

/// 逻辑宽度统一 390（与设计稿一致的手机宽度）。
const double _w = 390;

/// 固定渲染视口，避免输出分辨率随环境漂移。
void _viewport(WidgetTester tester, double logicalHeight, {double dpr = 2}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(_w * dpr, logicalHeight * dpr);
  addTearDown(tester.view.reset);
}

/// 组件级画框：白/奶油底 + 页面级水平内边距，内容不足时可滚动。
Widget _frame(Widget child, {double pad = AppSpacing.pageWide}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Container(
          width: _w,
          padding: EdgeInsets.all(pad),
          child: child,
        ),
      ),
    ),
  );
}

/// 页面级画框：整屏渲染（Scaffold/AppBar 已由页面自带）。
Widget _page(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: child,
    );

/// 渲染 + 快照。
Future<void> _shoot(
  WidgetTester tester,
  Widget app,
  String name, {
  double h = 900,
  double dpr = 2,
  bool settle = true,
}) async {
  _viewport(tester, h, dpr: dpr);
  await tester.pumpWidget(app);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('goldens/$name.png'));
}

// ───────────────────────────── 假数据 ─────────────────────────────

String _p2(int v) => v.toString().padLeft(2, '0');

String _stamp(DateTime d, int hh, int mm) =>
    '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(hh)}:${_p2(mm)}:00';

String _dateOnly(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';

final DateTime _today = DateTime.now();
final DateTime _monday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

Goal _goal({
  int id = 1,
  String periodType = 'weekly',
  int target = 20000,
  int current = 12400,
  int status = 0,
  String? endDate,
  String? startDate,
}) =>
    Goal(
      id: id,
      periodType: periodType,
      targetDistanceMeters: target,
      currentDistanceMeters: current,
      startDate: startDate ?? _dateOnly(_monday),
      endDate: endDate ?? _dateOnly(_monday.add(const Duration(days: 6))),
      status: status,
      createdAt: _stamp(_monday, 8, 0),
    );

ActivitySummary _act(
  int id,
  int meters,
  int secs, {
  int type = 1,
  int? pace,
  DateTime? day,
  int hh = 7,
  int mm = 12,
}) {
  final d = day ?? _today;
  final t = _stamp(d, hh, mm);
  return ActivitySummary(
    activityId: id,
    type: type,
    distanceMeters: meters,
    durationSeconds: secs,
    avgPace: pace ?? (meters > 0 ? (secs * 1000 / meters).round() : null),
    startTime: t,
    endTime: t,
    createdAt: t,
  );
}

User _user({String nickname = '林小跑', String uniqueId = 'CR-82413057', String phone = '138****2381'}) =>
    User(userId: 1, uniqueId: uniqueId, nickname: nickname, phone: phone);

/// 首页「有数据」活动列表：本周 4 次跑步 + 1 次骑行。
List<ActivitySummary> _homeActivities() => [
      _act(101, 5240, 1560, day: _today, hh: 7, mm: 12),
      _act(102, 8100, 2280, type: 2, day: _today, hh: 18, mm: 40),
      _act(103, 3000, 1020, day: _monday.add(const Duration(days: 2)), hh: 6, mm: 55),
      _act(104, 6420, 1980, day: _monday.add(const Duration(days: 1)), hh: 20, mm: 5),
      _act(105, 2100, 760, day: _monday, hh: 7, mm: 30),
    ];

// ── 假 Notifier（ProviderScope override 用）───────────────────────

class _FakeActivityList extends ActivityListNotifier {
  _FakeActivityList(this._items);
  final List<ActivitySummary> _items;
  @override
  Future<List<ActivitySummary>> build() async => _items;
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);
  final User? _user;
  @override
  Future<User?> build() async => _user;
}

class _FakeWs extends GlobalWsNotifier {
  final _controller = StreamController<WsMessage>.broadcast();
  @override
  GlobalWsStatus build() => GlobalWsStatus.connected;
  @override
  Stream<WsMessage> get messages => _controller.stream;
  @override
  Future<ChatMessage> sendMessage({
    required int receiverId,
    required String content,
    int? type,
    String? mediaUrl,
  }) async {
    return ChatMessage(
      messageId: 9001,
      senderId: 1,
      receiverId: receiverId,
      content: content,
      type: type ?? 1,
      mediaUrl: mediaUrl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 排行榜仓储桩：HomePage 内部私有的「上周排名」provider 会直接读仓储，
/// 覆盖 provider 挡不住它，因此这里把仓储也换掉，确保渲染过程零网络。
class _StubLeaderboardRepository extends LeaderboardRepository {
  _StubLeaderboardRepository(this.stub)
      : super(Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1')));

  final ({List<LeaderboardEntry> board, MyRank myRank}) stub;

  @override
  Future<PageResponse<LeaderboardEntry>> board({
    required String scope,
    required int type,
    String? period,
    int page = 1,
    int size = 50,
  }) async {
    return PageResponse<LeaderboardEntry>(total: stub.board.length, page: 1, size: 50, list: stub.board);
  }

  @override
  Future<MyRank> myRank({required String scope, required int type, String? period}) async => stub.myRank;
}

/// 全部读接口都返回假数据 / 立刻失败，绝不发网络请求。
List<Override> _overrides({
  List<ActivitySummary>? activities,
  List<Goal>? goals,
  List<LeaderboardEntry>? board,
  MyRank? myRank,
  List<models.Badge>? badges,
  List<FriendItem>? friends,
  List<FriendRequest>? requests,
  PageResponse<UserBrief>? search,
  PageResponse<ChatMessage>? history,
  ActivityDetail? detail,
  User? user,
  Object? boardError,
  Object? friendError,
}) {
  return [
    activityListProvider.overrideWith(() => _FakeActivityList(activities ?? const [])),
    activityDetailProvider.overrideWith((ref, arg) {
      if (detail == null) return Future.error(const ApiException(-1, '加载失败，请稍后重试'));
      return Future.value(detail);
    }),
    // user 为 null 即「未登录」，用于渲染个人中心的未登录空态。
    authProvider.overrideWith(() => _FakeAuth(user)),
    globalWsProvider.overrideWith(_FakeWs.new),
    goalListProvider.overrideWith((ref) async => goals ?? const <Goal>[]),
    badgeAllProvider.overrideWith((ref) async => badges ?? const <models.Badge>[]),
    badgeMineProvider.overrideWith((ref) async => const <UserBadge>[]),
    friendListProvider.overrideWith((ref) async {
      if (friendError != null) throw friendError;
      return friends ?? const <FriendItem>[];
    }),
    friendRequestsProvider.overrideWith((ref) async => requests ?? const <FriendRequest>[]),
    friendSearchProvider.overrideWith((ref, kw) async => search ?? PageResponse<UserBrief>(total: 0, page: 1, size: 20, list: const [])),
    messageHistoryProvider.overrideWith((ref, id) async =>
        history ?? PageResponse<ChatMessage>(total: 0, page: 1, size: 20, list: const [])),
    leaderboardProvider.overrideWith((ref, key) async {
      if (boardError != null) throw boardError;
      return board ?? const <LeaderboardEntry>[];
    }),
    myRankProvider.overrideWith((ref, key) async => myRank ?? const MyRank(rank: null, distanceMeters: 0, total: 0)),
    leaderboardRepositoryProvider.overrideWith(
      (ref) => _StubLeaderboardRepository((
        board: board ?? const <LeaderboardEntry>[],
        myRank: myRank ?? const MyRank(rank: null, distanceMeters: 0, total: 0),
      )),
    ),
  ];
}

// ───────────────────────────── 用例 ─────────────────────────────

void main() {
  setUpAll(_loadCjkFont);

  // ═══ A. 首页整页（数据态 / 空态） ═══

  testWidgets('A1 首页整页 · 数据态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          activities: _homeActivities(),
          goals: [_goal()],
          myRank: const MyRank(rank: 4, distanceMeters: 12400, total: 86),
          user: _user(),
        ),
        child: _page(const HomePage()),
      ),
      'vq_A1_home_loaded',
      h: 1500,
    );
  });

  testWidgets('A2 首页整页 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(user: _user(), badges: const [], goals: const []),
        child: _page(const HomePage()),
      ),
      'vq_A2_home_empty',
      h: 1300,
    );
  });

  // ═══ B. 首页各区块（独立组件） ═══

  testWidgets('B1 Hero 数据态 + 空态 + 三栏统计', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: _frame(Column(children: [
          const HomeTopBar(dateText: '周五 · 10月3日 · 晴 18°'),
          const SizedBox(height: AppSpacing.block),
          HomeHeroGoalCard(
            distanceText: '2.4',
            targetText: '3.0',
            remainingText: '0.6',
            weekRunCount: 4,
            progress: 0.8,
            onStart: () {},
          ),
          const SizedBox(height: AppSpacing.block),
          HomeTodayStatStrip(
            hasData: true,
            distanceText: '2.4',
            durationText: '18:32',
            paceText: '6\'30"',
            showDelta: true,
            deltaPositive: true,
            deltaText: '+0.6 km',
            onStartRun: () {},
          ),
          const SizedBox(height: AppSpacing.block),
          HomeTodayStatStrip(
            hasData: false,
            distanceText: '0.0',
            durationText: '0:00',
            paceText: '—',
            showDelta: false,
            deltaPositive: true,
            deltaText: '',
            onStartRun: () {},
          ),
        ])),
      ),
      'vq_B1_home_hero_stats',
      h: 900,
    );
  });

  testWidgets('B2 Hero 空态 + 本周跑量 + 校园榜行', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: _frame(Column(children: [
          HomeEmptyHero(onStart: () {}),
          const SizedBox(height: AppSpacing.block),
          HomeWeeklyVolumeCard(
            values: [2100, 6420, 3000, 0, 5240, 0, 0],
            todayIndex: 4,
            totalText: '16.8',
            goalText: '周目标 20 km',
            progressText: '完成 62%',
            lastWeekText: '较上周 +2.1 km',
            onStartRun: () {},
          ),
          const SizedBox(height: AppSpacing.block),
          HomeWeeklyVolumeCard(
            values: const [0, 0, 0, 0, 0, 0, 0],
            todayIndex: 4,
            totalText: null,
            goalText: '周目标 20 km',
            progressText: null,
            lastWeekText: null,
            onStartRun: () {},
          ),
          const SizedBox(height: AppSpacing.block),
          const HomeCampusRankRow(rank: 4, total: 86, lastWeekRank: 9),
          const SizedBox(height: AppSpacing.block),
          const HomeCampusRankRow(rank: null, total: 0, lastWeekRank: null),
        ])),
      ),
      'vq_B2_home_weekly_rank',
      h: 900,
    );
  });

  testWidgets('B3 运动目标区块 + 近期运动区块（数据 / 空态）', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: _frame(Column(children: [
          HomeGoalSection(goals: [_goal()], onSetGoal: () {}, onSeeAll: () {}),
          const SizedBox(height: AppSpacing.block),
          HomeGoalSection(goals: const [], onSetGoal: () {}, onSeeAll: () {}),
          const SizedBox(height: AppSpacing.block),
          HomeActivityList(
            items: _homeActivities(),
            onStartRun: () {},
            onSeeAll: () {},
            onItemTap: (_) {},
          ),
          const SizedBox(height: AppSpacing.block),
          HomeActivityList(items: const [], onStartRun: () {}, onSeeAll: () {}),
        ])),
      ),
      'vq_B3_home_goal_activity',
      h: 1100,
    );
  });

  // ═══ C. core/widgets 原子组件总览 ═══

  testWidgets('C1 原子组件总览（按钮/chip/卡片/指标/环/柱）', (tester) async {
    await _shoot(
      tester,
      _frame(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AppSectionTitle(title: '区块标题 + 查看全部', onSeeAll: _noop),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: const [
          AppChip(label: '选中', selected: true),
          AppChip(label: '未选中'),
          AppChip(label: '带图标', icon: Icons.directions_run),
          AppDeltaChip(text: '+0.6 km', positive: true, showIcon: true),
          AppDeltaChip(text: '-0.4 km', positive: false, showIcon: true),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: const [
          AppTextAction(label: '文字动作'),
          AppTextAction(label: '带图标', icon: Icons.chevron_right),
          AppTextAction(label: '下划线', underline: true),
        ]),
        const SizedBox(height: AppSpacing.md),
        const PrimaryButton(label: '主按钮', onPressed: _noop),
        const SizedBox(height: AppSpacing.sm),
        const PrimaryButton(label: '禁用态'),
        const SizedBox(height: AppSpacing.sm),
        const PrimaryButton(label: '加载中', loading: true, onPressed: _noop),
        const SizedBox(height: AppSpacing.md),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: const [
          AppProgressRing(value: 0.8),
          AppProgressRing(value: 0.0),
          AppProgressRing(value: 1.0, size: 64, strokeWidth: 6),
        ]),
        const SizedBox(height: AppSpacing.md),
        const AppMiniBarChart(
          values: [2100, 6420, 3000, 0, 5200, 0, 0],
          highlightIndex: 4,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(children: const [
          Expanded(child: AppMetricText(value: '2.4', unit: 'km', label: '距离 (km)')),
          Expanded(child: AppMetricText(value: '18:32', label: '时长 (分:秒)')),
          Expanded(child: AppMetricText(value: '743', label: '配速 (/km)')),
        ]),
        const SizedBox(height: AppSpacing.md),
        Row(children: const [
          UserAvatar(nickname: '林小跑', size: 44),
          SizedBox(width: 8),
          UserAvatar(nickname: '张三', size: 64),
          SizedBox(width: 8),
          UserAvatar(size: 40),
        ]),
      ])),
      'vq_C1_core_widgets',
      h: 1100,
      // AppProgressRing 内含 CircularProgressIndicator，其动画永不结束，
      // pumpAndSettle 会超时；这里固定推一帧即可。
      settle: false,
    );
  });

  testWidgets('C2 空态 / 错误态组件（页面级 + 区块级）', (tester) async {
    await _shoot(
      tester,
      _frame(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('EmptyState（页面级空态）',
            style: TextStyle(fontSize: AppFontSize.title, fontWeight: AppFontWeight.bold)),
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.directions_run,
            title: '还没有运动记录',
            subtitle: '去跑一跑，留下你的第一条轨迹',
            actionLabel: '去跑步',
            onAction: _noop,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('AppEmptyHint（区块级空态）',
            style: TextStyle(fontSize: AppFontSize.title, fontWeight: AppFontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        AppEmptyHint(
          icon: Icons.directions_run,
          iconBoxSize: 56,
          title: '还没有运动记录',
          description: '去跑一跑，留下你的第一条轨迹',
          action: AppTextAction(label: '去跑步', icon: Icons.arrow_forward_ios, onTap: _noop),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('ErrorState（错误态）',
            style: TextStyle(fontSize: AppFontSize.title, fontWeight: AppFontWeight.bold)),
        SizedBox(
          height: 260,
          child: ErrorState(
            title: '加载失败',
            message: '网络连接失败，请检查网络后重试',
            onRetry: _noop,
          ),
        ),
      ]), pad: AppSpacing.pageWide),
      'vq_C2_states',
      h: 1100,
    );
  });

  // ═══ D. 认证页（无需 provider 数据，但需要 ProviderScope） ═══

  testWidgets('D1 登录页', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const LoginPage())),
      'vq_D1_login',
      h: 844,
    );
  });

  testWidgets('D2 注册页', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const RegisterPage())),
      'vq_D2_register',
      h: 844,
    );
  });

  // ═══ E. 排行榜 ═══

  testWidgets('E1 排行榜 · 数据态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          board: const [
            LeaderboardEntry(rank: 1, userId: 2, uniqueId: 'CR-10000001', nickname: '陈飞宇', distanceMeters: 42800),
            LeaderboardEntry(rank: 2, userId: 3, uniqueId: 'CR-10000002', nickname: '王梓涵', distanceMeters: 38100),
            LeaderboardEntry(rank: 3, userId: 4, uniqueId: 'CR-10000003', nickname: '刘雨桐', distanceMeters: 31500),
            LeaderboardEntry(rank: 4, userId: 1, uniqueId: 'CR-82413057', nickname: '林小跑', distanceMeters: 12400),
            LeaderboardEntry(rank: 5, userId: 6, uniqueId: 'CR-10000005', nickname: '赵一鸣', distanceMeters: 9800),
            LeaderboardEntry(rank: 6, userId: 7, uniqueId: 'CR-10000006', nickname: '孙宁', distanceMeters: 7200),
          ],
          myRank: const MyRank(rank: 4, distanceMeters: 12400, total: 86),
        ),
        child: _page(const LeaderboardPage()),
      ),
      'vq_E1_leaderboard',
      h: 900,
    );
  });

  testWidgets('E2 排行榜 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: _page(const LeaderboardPage()),
      ),
      'vq_E2_leaderboard_empty',
      h: 844,
    );
  });

  testWidgets('E3 排行榜 · 错误态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(boardError: const ApiException(-1, '网络连接失败，请检查网络后重试')),
        child: _page(const LeaderboardPage()),
      ),
      'vq_E3_leaderboard_error',
      h: 844,
    );
  });

  // ═══ F. 我的 / 勋章 / 通知 ═══

  testWidgets('F1 个人中心 · 已登录', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(user: _user()),
        child: _page(const ProfilePage()),
      ),
      'vq_F1_profile',
      h: 844,
    );
  });

  testWidgets('F2 个人中心 · 未登录空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const ProfilePage())),
      'vq_F2_profile_empty',
      h: 844,
    );
  });

  testWidgets('F3 勋章墙 · 有已获得 / 全未获得', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(badges: const [
          models.Badge(id: 1, code: 'FIRST_RUN', name: '初次起跑', description: '完成第一次运动', earned: true, awardedAt: '2026-09-30 07:20:00'),
          models.Badge(id: 2, code: 'WEEK_5', name: '周跑五练', description: '一周完成 5 次跑步', earned: true, awardedAt: '2026-10-02 21:00:00'),
          models.Badge(id: 3, code: 'DIST_10', name: '十公里达成', description: '单次跑满 10 公里'),
          models.Badge(id: 4, code: 'NIGHT_OWL', name: '夜跑达人', description: '夜间跑步 5 次'),
          models.Badge(id: 5, code: 'EARLY_BIRD', name: '清晨之翼', description: '早起跑步 5 次'),
          models.Badge(id: 6, code: 'FENCE_KING', name: '围栏之王', description: '围栏内跑满 30 天'),
        ]),
        child: _page(const BadgesPage()),
      ),
      'vq_F3_badges',
      h: 1000,
    );
  });

  testWidgets('F4 通知页 · 有通知', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          requests: const [
            FriendRequest(requestId: 1, userId: 9, uniqueId: 'CR-70000001', nickname: '周嘉禾', createdAt: '2026-10-03 09:12:00'),
          ],
          badges: const [],
          goals: [_goal(id: 7, target: 20000, current: 20000)],
        ),
        child: _page(const NotificationsPage()),
      ),
      'vq_F4_notifications',
      h: 844,
    );
  });

  testWidgets('F5 通知页 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const NotificationsPage())),
      'vq_F5_notifications_empty',
      h: 844,
    );
  });

  // ═══ G. 运动记录 ═══

  testWidgets('G1 运动记录列表 · 数据态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(activities: _homeActivities()),
        child: _page(const ActivityListPage()),
      ),
      'vq_G1_activity_list',
      h: 900,
    );
  });

  testWidgets('G2 运动记录列表 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const ActivityListPage())),
      'vq_G2_activity_list_empty',
      h: 844,
    );
  });

  testWidgets('G3 运动详情 · 无轨迹（空态可渲染；有轨迹需联网瓦片）', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          detail: ActivityDetail(
            activityId: 101,
            type: 1,
            distanceMeters: 5240,
            durationSeconds: 1560,
            avgPace: 298,
            calories: 312,
            startTime: _stamp(_today, 7, 12),
            endTime: _stamp(_today, 7, 38),
            createdAt: _stamp(_today, 7, 38),
            track: const [],
          ),
        ),
        child: _page(const ActivityDetailPage(activityId: 101)),
      ),
      'vq_G3_activity_detail',
      h: 1000,
    );
  });

  testWidgets('G4 运动详情 · 含轨迹（瓦片离线，仅验证折线/标记布局）', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          detail: ActivityDetail(
            activityId: 102,
            type: 1,
            invalid: 1,
            distanceMeters: 5240,
            durationSeconds: 1560,
            avgPace: 298,
            calories: 312,
            startTime: _stamp(_today, 7, 12),
            endTime: _stamp(_today, 7, 38),
            createdAt: _stamp(_today, 7, 38),
            track: List.generate(
              8,
              (i) => TrackPoint(
                latitude: 30.51 + i * 0.0006,
                longitude: 114.35 + i * 0.0004,
                timestamp: 1759456320000 + i * 30000,
              ),
            ),
          ),
        ),
        child: _page(const ActivityDetailPage(activityId: 102)),
      ),
      'vq_G4_activity_detail_track',
      h: 1000,
    );
  });

  // ═══ H. 社区 / 好友 / 聊天 ═══

  testWidgets('H1 社区（好友页）· 有申请 + 好友列表', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          requests: const [
            FriendRequest(requestId: 1, userId: 9, uniqueId: 'CR-70000001', nickname: '周嘉禾', createdAt: '2026-10-03 09:12:00'),
            FriendRequest(requestId: 2, userId: 10, uniqueId: 'CR-70000002', nickname: '吴桐', createdAt: '2026-10-02 21:40:00'),
          ],
          friends: const [
            FriendItem(friendshipId: 1, userId: 2, uniqueId: 'CR-10000001', nickname: '陈飞宇'),
            FriendItem(friendshipId: 2, userId: 3, uniqueId: 'CR-10000002', nickname: '王梓涵'),
            FriendItem(friendshipId: 3, userId: 4, uniqueId: 'CR-10000003', nickname: '刘雨桐'),
          ],
        ),
        child: _page(const FriendsPage()),
      ),
      'vq_H1_friends',
      h: 1000,
    );
  });

  testWidgets('H2 社区 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const FriendsPage())),
      'vq_H2_friends_empty',
      h: 844,
    );
  });

  testWidgets('H3 社区 · 好友列表错误态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(friendError: const ApiException(-1, '网络连接失败，请检查网络后重试')),
        child: _page(const FriendsPage()),
      ),
      'vq_H3_friends_error',
      h: 844,
    );
  });

  testWidgets('H4 添加好友（搜索页）· 引导态 + 结果态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const FriendsSearchPage())),
      'vq_H4_search_guide',
      h: 844,
    );
  });

  testWidgets('H5 添加好友 · 搜索结果', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          search: const PageResponse<UserBrief>(
            total: 2,
            page: 1,
            size: 20,
            list: [
              UserBrief(userId: 11, uniqueId: 'CR-10000011', nickname: '郑一诺'),
              UserBrief(userId: 12, uniqueId: 'CR-10000012', nickname: '黄子墨'),
            ],
          ),
        ),
        child: _page(const FriendsSearchPage()),
      ),
      'vq_H5_search_results',
      h: 844,
    );
  });

  testWidgets('H6 聊天页 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(user: _user()),
        child: _page(const ChatPage(friendId: 2, friendName: '陈飞宇')),
      ),
      'vq_H6_chat_empty',
      h: 844,
    );
  });

  testWidgets('H7 聊天页 · 有消息（含已读/失败态）', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(
          user: _user(),
          history: PageResponse<ChatMessage>(
            total: 4,
            page: 1,
            size: 20,
            list: [
              ChatMessage(messageId: 4, senderId: 2, receiverId: 1, content: '明早六点半操场见？', timestamp: now - 60000),
              ChatMessage(messageId: 3, senderId: 1, receiverId: 2, content: '好呀，我七点前到', timestamp: now - 300000, readAt: now - 240000),
              ChatMessage(messageId: 2, senderId: 2, receiverId: 1, content: '今天跑了 5 公里，配速 6\'30"', timestamp: now - 900000),
              ChatMessage(messageId: 1, senderId: 1, receiverId: 2, content: '厉害！继续保持', timestamp: now - 1200000, readAt: now - 1100000),
            ],
          ),
        ),
        child: _page(const ChatPage(friendId: 2, friendName: '陈飞宇')),
      ),
      'vq_H7_chat_messages',
      h: 844,
    );
  });

  // ═══ I. 运动目标页 ═══

  testWidgets('I1 运动目标 · 列表（进行中 / 已完成 / 已过期）', (tester) async {
    await _shoot(
      tester,
      ProviderScope(
        overrides: _overrides(goals: [
          _goal(id: 1, target: 20000, current: 12400),
          _goal(id: 2, periodType: 'monthly', target: 80000, current: 80000, status: 1),
          _goal(id: 3, periodType: 'custom', target: 5000, current: 1200, status: 2),
        ]),
        child: _page(const GoalsPage()),
      ),
      'vq_I1_goals',
      h: 1100,
    );
  });

  testWidgets('I2 运动目标 · 空态', (tester) async {
    await _shoot(
      tester,
      ProviderScope(overrides: _overrides(), child: _page(const GoalsPage())),
      'vq_I2_goals_empty',
      h: 844,
    );
  });
}

void _noop() {}
