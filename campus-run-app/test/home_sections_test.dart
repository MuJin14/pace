import 'package:campus_run_app/data/models/activity_summary.dart';
import 'package:campus_run_app/data/models/goal.dart';
import 'package:campus_run_app/features/home/widgets/home_activity_list.dart';
import 'package:campus_run_app/features/home/widgets/home_goal_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页区块组件测试：空态 / 有数据态 / 回调注入。
/// 两个组件都是纯展示组件（跳转由页面注入），因此可以不依赖 go_router 独立测试。
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );

String _pad2(int v) => v.toString().padLeft(2, '0');

/// 后端 `yyyy-MM-dd HH:mm:ss` 格式的本地时间串。
String _stamp(DateTime day, int hour, int minute) =>
    '${day.year}-${_pad2(day.month)}-${_pad2(day.day)} '
    '${_pad2(hour)}:${_pad2(minute)}:00';

String _dateOnly(DateTime day) =>
    '${day.year}-${_pad2(day.month)}-${_pad2(day.day)}';

Goal _goal({
  int id = 1,
  int target = 10000,
  int current = 4000,
  String periodType = 'weekly',
  int status = 0,
  String? endDate,
}) =>
    Goal(
      id: id,
      periodType: periodType,
      targetDistanceMeters: target,
      currentDistanceMeters: current,
      status: status,
      endDate: endDate,
    );

ActivitySummary _activity({
  int id = 1,
  int type = 1,
  int distanceMeters = 5000,
  int durationSeconds = 2530,
  int? avgPace = 390,
  String startTime = '2020-03-05 09:08:00',
}) =>
    ActivitySummary(
      activityId: id,
      type: type,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      avgPace: avgPace,
      startTime: startTime,
      endTime: startTime,
      createdAt: startTime,
    );

/// 环比文案形如 `+1.0 km` / `-0.5 km`。
Finder _deltaTexts() => find.byWidgetPredicate((Widget w) {
      final data = w is Text ? w.data : null;
      return data != null && RegExp(r'^[+-]\d+\.\d km$').hasMatch(data);
    });

void main() {
  group('HomeGoalSection 空态', () {
    testWidgets('没有目标时展示召唤语与「设置目标」动作', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: const <Goal>[],
        onSetGoal: () => taps++,
      )));

      expect(find.text('运动目标'), findsOneWidget);
      expect(find.text('还没有进行中的目标'), findsOneWidget);
      expect(find.text('设置目标'), findsOneWidget);
      expect(find.text('查看全部'), findsNothing);

      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('全部目标已完成时仍是空态', (tester) async {
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [
          _goal(id: 1, target: 1000, current: 1000, status: 1),
          _goal(id: 2, target: 1000, current: 300, status: 2),
        ],
        onSetGoal: () {},
      )));

      expect(find.text('还没有进行中的目标'), findsOneWidget);
      expect(find.text('设置目标'), findsOneWidget);
    });

    testWidgets('onSeeAll 提供时展示「查看全部」并可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: const <Goal>[],
        onSetGoal: () {},
        onSeeAll: () => taps++,
      )));

      expect(find.text('查看全部'), findsOneWidget);
      await tester.tap(find.text('查看全部'));
      expect(taps, 1);
    });
  });

  group('HomeGoalSection 有数据态', () {
    testWidgets('进度卡展示周期、目标距离、百分比与剩余距离', (tester) async {
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(target: 10000, current: 4000)],
        onSetGoal: () {},
      )));

      expect(find.text('每周 10.00 km'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('本周还差 6.00 km'), findsOneWidget);
      expect(find.text('还没有进行中的目标'), findsNothing);
    });

    testWidgets('周期标签：monthly → 每月，custom → 目标，未知 → 每周', (tester) async {
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(target: 10000, current: 0, periodType: 'monthly')],
        onSetGoal: () {},
      )));
      expect(find.text('每月 10.00 km'), findsOneWidget);

      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(target: 10000, current: 0, periodType: 'custom')],
        onSetGoal: () {},
      )));
      expect(find.text('目标 10.00 km'), findsOneWidget);

      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(target: 10000, current: 0, periodType: 'fortnight')],
        onSetGoal: () {},
      )));
      expect(find.text('每周 10.00 km'), findsOneWidget);
    });

    testWidgets('有截止日期时追加剩余天数', (tester) async {
      final threeDaysLater = DateTime.now().add(const Duration(days: 3));
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(endDate: _dateOnly(threeDaysLater))],
        onSetGoal: () {},
      )));

      expect(find.text('本周还差 6.00 km · 还剩 3 天'), findsOneWidget);
    });

    testWidgets('已过期显示还剩 0 天；日期非法则不显示剩余天数', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(endDate: _dateOnly(yesterday))],
        onSetGoal: () {},
      )));
      expect(find.text('本周还差 6.00 km · 还剩 0 天'), findsOneWidget);

      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(endDate: 'not-a-date')],
        onSetGoal: () {},
      )));
      expect(find.text('本周还差 6.00 km'), findsOneWidget);
      expect(find.textContaining('还剩'), findsNothing);
    });

    testWidgets('超额完成时进度封顶 100%，剩余距离为 0 m', (tester) async {
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(target: 1000, current: 5000)],
        onSetGoal: () {},
      )));

      expect(find.text('每周 1.00 km'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('本周还差 0 m'), findsOneWidget);
    });

    testWidgets('目标距离为 0 时不除零，进度 0%', (tester) async {
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [_goal(target: 0, current: 0)],
        onSetGoal: () {},
      )));

      expect(find.text('每周 0 m'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('本周还差 0 m'), findsOneWidget);
    });

    testWidgets('多个目标时取第一个进行中的目标', (tester) async {
      await tester.pumpWidget(_host(HomeGoalSection(
        goals: [
          _goal(id: 1, target: 9000, current: 9000, status: 1),
          _goal(id: 2, target: 1000, current: 500),
          _goal(id: 3, target: 2000, current: 2000),
        ],
        onSetGoal: () {},
      )));

      expect(find.text('每周 1.00 km'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('每周 2.00 km'), findsNothing);
    });
  });

  group('HomeActivityList 空态', () {
    testWidgets('无记录时展示召唤语与「去跑步」动作', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(HomeActivityList(
        items: const <ActivitySummary>[],
        onStartRun: () => taps++,
      )));

      expect(find.text('近期运动'), findsOneWidget);
      expect(find.text('还没有运动记录'), findsOneWidget);
      expect(find.text('去跑一跑，留下你的第一条轨迹'), findsOneWidget);
      expect(find.text('去跑步'), findsOneWidget);
      expect(find.text('查看全部'), findsNothing);

      await tester.tap(find.text('去跑步'));
      expect(taps, 1);
    });

    testWidgets('take 为 0 或负数时等同于空态', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [_activity()],
        take: 0,
        onStartRun: () {},
      )));
      expect(find.text('还没有运动记录'), findsOneWidget);

      await tester.pumpWidget(_host(HomeActivityList(
        items: [_activity()],
        take: -1,
        onStartRun: () {},
      )));
      expect(find.text('还没有运动记录'), findsOneWidget);
    });

    testWidgets('onSeeAll 提供时展示「查看全部」并可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(HomeActivityList(
        items: [_activity()],
        onStartRun: () {},
        onSeeAll: () => taps++,
      )));

      expect(find.text('查看全部'), findsOneWidget);
      await tester.tap(find.text('查看全部'));
      expect(taps, 1);
    });
  });

  group('HomeActivityList 有数据态', () {
    final today = DateTime.now();
    final todayStamp = _stamp(today, 12, 34);

    testWidgets('最多展示 take 条（默认 3），并展示标题/时长/配速', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(id: 1, distanceMeters: 5000, startTime: todayStamp),
          _activity(id: 2, distanceMeters: 4000, durationSeconds: 1800,
              avgPace: 400, startTime: todayStamp),
          _activity(
              id: 3,
              type: 2,
              distanceMeters: 3000,
              durationSeconds: 900,
              avgPace: 300,
              startTime: todayStamp),
          _activity(id: 4, distanceMeters: 2000, startTime: todayStamp),
        ],
        onStartRun: () {},
      )));

      expect(find.text('跑步 · 5.00 km'), findsOneWidget);
      expect(find.text('跑步 · 4.00 km'), findsOneWidget);
      expect(find.text('骑行 · 3.00 km'), findsOneWidget);
      expect(find.text('跑步 · 2.00 km'), findsNothing);

      expect(find.text('42:10'), findsOneWidget);
      expect(find.text('30:00'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);

      expect(find.textContaining('今天 12:34'), findsNWidgets(3));
      expect(find.textContaining('配速 6\'30"'), findsOneWidget);
      expect(find.textContaining('配速 5\'00"'), findsOneWidget);
      expect(find.byIcon(Icons.directions_run), findsNWidgets(2));
      expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    });

    testWidgets('环比：与更早一条同类型记录比较，类型不同或持平不显示', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(id: 1, distanceMeters: 5000, startTime: todayStamp),
          _activity(id: 2, distanceMeters: 4000, startTime: todayStamp),
          _activity(id: 3, type: 2, distanceMeters: 3000,
              startTime: todayStamp),
        ],
        onStartRun: () {},
      )));

      // 第 1 条与第 2 条同为跑步：+1.0 km；第 2 条与第 3 条类型不同；第 3 条无后继。
      expect(find.text('+1.0 km'), findsOneWidget);
      expect(_deltaTexts(), findsOneWidget);
    });

    testWidgets('距离变少显示负值环比', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(id: 1, distanceMeters: 3000, startTime: todayStamp),
          _activity(id: 2, distanceMeters: 4000, startTime: todayStamp),
        ],
        onStartRun: () {},
      )));

      expect(find.text('-1.0 km'), findsOneWidget);
      expect(_deltaTexts(), findsOneWidget);
    });

    testWidgets('距离持平不显示环比', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(id: 1, distanceMeters: 5000, startTime: todayStamp),
          _activity(id: 2, distanceMeters: 5000, startTime: todayStamp),
        ],
        onStartRun: () {},
      )));

      expect(_deltaTexts(), findsNothing);
    });

    testWidgets('take 大于列表长度时渲染全部', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(id: 1, distanceMeters: 5000, startTime: todayStamp),
          _activity(id: 2, distanceMeters: 4000, startTime: todayStamp),
        ],
        take: 10,
        onStartRun: () {},
      )));

      expect(find.text('跑步 · 5.00 km'), findsOneWidget);
      expect(find.text('跑步 · 4.00 km'), findsOneWidget);
    });

    testWidgets('相对时间：昨天与更早日期', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(
              id: 1,
              startTime: _stamp(
                  today.subtract(const Duration(days: 1)), 23, 5)),
          _activity(id: 2, startTime: '2020-03-05 09:08:00'),
        ],
        onStartRun: () {},
      )));

      expect(find.textContaining('昨天 23:05'), findsOneWidget);
      expect(find.textContaining('3月5日 09:08'), findsOneWidget);
    });

    testWidgets('startTime 无法解析时原样展示，配速缺失显示占位', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [_activity(avgPace: null, startTime: 'oops')],
        onStartRun: () {},
      )));

      expect(find.textContaining('oops'), findsOneWidget);
      expect(find.text('oops · 配速 —'), findsOneWidget);
    });

    testWidgets('onItemTap 注入时点击行回调对应记录', (tester) async {
      ActivitySummary? tapped;
      await tester.pumpWidget(_host(HomeActivityList(
        items: [
          _activity(id: 11, distanceMeters: 5000, startTime: todayStamp),
          _activity(id: 12, distanceMeters: 4000, startTime: todayStamp),
        ],
        onStartRun: () {},
        onItemTap: (item) => tapped = item,
      )));

      final row = find.ancestor(
        of: find.text('跑步 · 5.00 km'),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(row.first).onTap, isNotNull);

      await tester.tap(find.text('跑步 · 5.00 km'));
      expect(tapped?.activityId, 11);
    });

    testWidgets('onItemTap 为 null 时行不可点', (tester) async {
      await tester.pumpWidget(_host(HomeActivityList(
        items: [_activity(id: 11, distanceMeters: 5000, startTime: todayStamp)],
        onStartRun: () {},
      )));

      final row = find.ancestor(
        of: find.text('跑步 · 5.00 km'),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(row.first).onTap, isNull);
    });
  });
}
