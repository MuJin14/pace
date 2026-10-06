import 'package:campus_run_app/core/theme/app_theme.dart';
import 'package:campus_run_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `core/widgets` 原子组件测试：固定尺寸 + MaterialApp 包裹，断言文案、回调与关键样式，
/// 不做像素级快照。所有动画类断言只用 `pump()`，避免 `pumpAndSettle` 超时。
///
/// 内层 `Center` 是关键：否则自适应组件会被外层 SizedBox 的紧约束拉伸成整块画布，
/// `tester.getSize(组件)` 量到的就不是组件自身尺寸（AppProgressRing / UserAvatar 曾因此失败）。
Widget _host(Widget child, {double width = 390, double height = 600}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

Finder _inside(Type type, Finder matching) =>
    find.descendant(of: find.byType(type), matching: matching);

Finder _barsWithColor(Color color) => _inside(
      AppMiniBarChart,
      find.byWidgetPredicate((Widget w) {
        if (w is! Container) return false;
        final decoration = w.decoration;
        return decoration is BoxDecoration && decoration.color == color;
      }),
    );

void main() {
  group('AppCard', () {
    testWidgets('渲染子组件，onTap 触发一次回调', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppCard(
        onTap: () => taps++,
        child: const Text('卡片内容'),
      )));

      expect(find.text('卡片内容'), findsOneWidget);
      expect(_inside(AppCard, find.byType(InkWell)), findsOneWidget);

      await tester.tap(find.text('卡片内容'));
      expect(taps, 1);
    });

    testWidgets('无 onTap 时是静态容器（无水波纹）', (tester) async {
      await tester.pumpWidget(_host(const AppCard(child: Text('静态卡片'))));

      expect(find.text('静态卡片'), findsOneWidget);
      expect(_inside(AppCard, find.byType(InkWell)), findsNothing);
    });

    testWidgets('默认内边距 16，radius/borderColor/margin 生效', (tester) async {
      await tester.pumpWidget(_host(const AppCard(
        radius: AppRadius.lg,
        borderColor: AppColors.divider,
        margin: EdgeInsets.all(AppSpacing.sm),
        child: Text('样式卡片'),
      )));

      // 不数 Padding 个数：传了 borderColor 时 Container 会额外插入一个
      // 1px 的装饰内边距（BoxDecoration.padding == border.dimensions），
      // 因此断言「存在 margin 与默认内边距这两个具体值」。
      final paddings = tester
          .widgetList<Padding>(_inside(AppCard, find.byType(Padding)))
          .map((Padding p) => p.padding);
      expect(paddings, contains(const EdgeInsets.all(AppSpacing.sm)));
      expect(paddings, contains(const EdgeInsets.all(AppSpacing.md)));

      final container = tester.widget<Container>(
        _inside(AppCard, find.byType(Container)).first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.lg));
      expect(decoration.border, isNotNull);
      expect(decoration.color, AppColors.card);
    });
  });

  group('AppChip', () {
    testWidgets('未选中：白底灰字，点击回调', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          _host(AppChip(label: '全部', onTap: () => taps++)));

      final label = tester.widget<Text>(find.text('全部'));
      expect(label.style?.color, AppColors.textSecondary);
      expect(label.style?.fontSize, AppFontSize.body);
      expect(
        tester
            .widget<Material>(_inside(AppChip, find.byType(Material)))
            .color,
        AppColors.card,
      );

      await tester.tap(find.text('全部'));
      expect(taps, 1);
    });

    testWidgets('选中：主色底白字', (tester) async {
      await tester.pumpWidget(
          _host(const AppChip(label: '跑步', selected: true)));

      expect(
        tester.widget<Text>(find.text('跑步')).style?.color,
        AppColors.onPrimary,
      );
      expect(
        tester
            .widget<Material>(_inside(AppChip, find.byType(Material)))
            .color,
        AppColors.primary,
      );
    });

    testWidgets('可带前置图标', (tester) async {
      await tester.pumpWidget(_host(const AppChip(
        label: '骑行',
        icon: Icons.directions_bike,
      )));
      expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    });

    testWidgets('无 onTap 时不响应点击（onTap 为 null）', (tester) async {
      await tester.pumpWidget(_host(const AppChip(label: '只读')));
      expect(
        tester.widget<InkWell>(_inside(AppChip, find.byType(InkWell))).onTap,
        isNull,
      );
    });
  });

  group('AppSectionTitle', () {
    testWidgets('只有标题，onSeeAll 为 null 时不渲染「查看全部」', (tester) async {
      await tester.pumpWidget(_host(const AppSectionTitle(title: '运动目标')));

      final title = tester.widget<Text>(find.text('运动目标'));
      expect(title.style?.fontSize, AppFontSize.title);
      expect(title.style?.fontWeight, AppFontWeight.bold);
      expect(title.style?.color, AppColors.textPrimary);
      expect(find.text('查看全部'), findsNothing);
    });

    testWidgets('提供 onSeeAll 时渲染并可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppSectionTitle(
        title: '近期运动',
        onSeeAll: () => taps++,
      )));

      expect(find.text('查看全部'), findsOneWidget);
      await tester.tap(find.text('查看全部'));
      expect(taps, 1);
    });
  });

  group('AppTextAction', () {
    testWidgets('文字链可点击，带图标与下划线', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppTextAction(
        label: '查看全部',
        icon: Icons.chevron_right,
        underline: true,
        onTap: () => taps++,
      )));

      expect(find.text('查看全部'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      final text = tester.widget<Text>(find.text('查看全部'));
      expect(text.style?.decoration, TextDecoration.underline);
      expect(text.style?.color, AppColors.accentHot);

      await tester.tap(find.text('查看全部'));
      expect(taps, 1);
    });

    testWidgets('自定义颜色与字号生效', (tester) async {
      await tester.pumpWidget(_host(const AppTextAction(
        label: '去跑步',
        color: AppColors.primary,
        fontSize: AppFontSize.caption,
      )));

      final text = tester.widget<Text>(find.text('去跑步'));
      expect(text.style?.color, AppColors.primary);
      expect(text.style?.fontSize, AppFontSize.caption);
      expect(text.style?.decoration, isNull);
    });
  });

  group('AppEmptyHint', () {
    testWidgets('column 布局：标题 + 说明 + 胶囊动作可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppEmptyHint(
        title: '今天还没跑',
        description: '完成第一次跑步，点亮今日徽章',
        actionLabel: '开始跑步',
        onAction: () => taps++,
      )));

      expect(find.text('今天还没跑'), findsOneWidget);
      expect(find.text('完成第一次跑步，点亮今日徽章'), findsOneWidget);
      expect(find.text('开始跑步'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('只有 actionLabel 没有 onAction 时不生成按钮', (tester) async {
      await tester.pumpWidget(_host(const AppEmptyHint(
        title: '今天还没跑',
        actionLabel: '开始跑步',
      )));

      expect(find.text('开始跑步'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('自定义 action 优先于 actionLabel', (tester) async {
      await tester.pumpWidget(_host(AppEmptyHint(
        title: '今天还没跑',
        actionLabel: '被忽略',
        onAction: () {},
        action: const Text('自定义动作'),
      )));

      expect(find.text('自定义动作'), findsOneWidget);
      expect(find.text('被忽略'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('row 布局：图标圆底尺寸与文案左对齐', (tester) async {
      await tester.pumpWidget(_host(const AppEmptyHint(
        layout: AppEmptyHintLayout.row,
        icon: Icons.directions_run,
        iconBoxSize: 56,
        title: '还没有运动记录',
        description: '去跑一跑，留下你的第一条轨迹',
      )));

      expect(find.byIcon(Icons.directions_run), findsOneWidget);
      expect(
        tester.getSize(_inside(AppEmptyHint, find.byType(Container)).first),
        const Size(56, 56),
      );
      final title = tester.widget<Text>(find.text('还没有运动记录'));
      expect(title.textAlign, TextAlign.start);
    });

    testWidgets('actionFullWidth 时按钮撑满宽度', (tester) async {
      await tester.pumpWidget(_host(AppEmptyHint(
        title: '今天是空的',
        actionLabel: '去跑步',
        actionFullWidth: true,
        onAction: () {},
      )));

      final box = tester.widget<SizedBox>(
        find
            .ancestor(
                of: find.byType(FilledButton), matching: find.byType(SizedBox))
            .first,
      );
      expect(box.width, double.infinity);
      expect(box.height, 48);
    });
  });

  group('EmptyState', () {
    testWidgets('页面级空态：图标 + 标题 + 说明 + 动作', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(EmptyState(
        icon: Icons.inbox_outlined,
        title: '还没有好友',
        subtitle: '搜索专属 ID 添加好友',
        actionLabel: '去搜索',
        onAction: () => taps++,
      )));

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('还没有好友'), findsOneWidget);
      expect(find.text('搜索专属 ID 添加好友'), findsOneWidget);
      expect(
        tester.getSize(_inside(EmptyState, find.byType(Container)).first),
        const Size(88, 88),
      );

      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('无动作时不渲染按钮', (tester) async {
      await tester.pumpWidget(_host(const EmptyState(
        icon: Icons.inbox_outlined,
        title: '还没有好友',
      )));

      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('ErrorState', () {
    testWidgets('只有错误信息，无 onRetry 时不渲染按钮', (tester) async {
      await tester.pumpWidget(_host(const ErrorState(message: '网络异常')));

      expect(find.text('网络异常'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('onRetry 生成「重试」按钮并回调', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_host(ErrorState(
        title: '加载失败',
        message: '网络异常',
        onRetry: () => retries++,
      )));

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      expect(retries, 1);
    });

    testWidgets('自定义 actionLabel；actionLabel 为空则不渲染按钮', (tester) async {
      await tester.pumpWidget(_host(ErrorState(
        message: '网络异常',
        actionLabel: '重新加载',
        onRetry: () {},
      )));
      expect(find.text('重新加载'), findsOneWidget);

      await tester.pumpWidget(_host(ErrorState(
        message: '网络异常',
        actionLabel: '',
        onRetry: () {},
      )));
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('自定义 action 优先于 onRetry', (tester) async {
      await tester.pumpWidget(_host(ErrorState(
        message: '网络异常',
        onRetry: () {},
        action: const Text('自定义按钮'),
      )));

      expect(find.text('自定义按钮'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });
  });

  group('PrimaryButton', () {
    testWidgets('默认展示文案并可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(PrimaryButton(
        label: '登录',
        icon: Icons.login,
        onPressed: () => taps++,
      )));

      expect(find.text('登录'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
      await tester.tap(find.text('登录'));
      expect(taps, 1);
    });

    testWidgets('onPressed 为 null 时禁用（半透明且不回调）', (tester) async {
      await tester.pumpWidget(_host(const PrimaryButton(label: '登录')));

      expect(find.text('登录'), findsOneWidget);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.6);
      expect(
        tester
            .widget<GestureDetector>(_inside(PrimaryButton, find.byType(GestureDetector)))
            .onTap,
        isNull,
      );
    });

    testWidgets('loading 时显示转圈、隐藏文案且不可点击', (tester) async {
      await tester.pumpWidget(_host(PrimaryButton(
        label: '登录',
        loading: true,
        onPressed: () {},
      )));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('登录'), findsNothing);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.6);
    });
  });

  group('AppMetricText', () {
    testWidgets('数字与单位在同一段富文本里', (tester) async {
      await tester.pumpWidget(
          _host(const AppMetricText(value: '5.2', unit: 'km')));

      expect(find.text('5.2 km'), findsOneWidget);
    });

    testWidgets('无单位时只有数字', (tester) async {
      await tester.pumpWidget(_host(const AppMetricText(value: '42')));

      expect(find.text('42'), findsOneWidget);
      expect(find.text('42 '), findsNothing);
    });

    testWidgets('label 默认在数字下方，labelAbove 时在上方', (tester) async {
      await tester.pumpWidget(_host(const AppMetricText(
        value: '5.2',
        unit: 'km',
        label: '距离',
      )));
      expect(
        tester.getTopLeft(find.text('距离')).dy,
        greaterThan(tester.getTopLeft(find.text('5.2 km')).dy),
      );

      await tester.pumpWidget(_host(const AppMetricText(
        value: '5.2',
        unit: 'km',
        label: '距离',
        labelAbove: true,
      )));
      expect(
        tester.getTopLeft(find.text('距离')).dy,
        lessThan(tester.getTopLeft(find.text('5.2 km')).dy),
      );
    });

    testWidgets('字号与颜色参数生效', (tester) async {
      await tester.pumpWidget(_host(const AppMetricText(
        value: '39.6',
        unit: 'km',
        valueSize: AppFontSize.metricHero,
        color: Colors.white,
      )));

      final rich = tester.widget<Text>(find.text('39.6 km'));
      final span = rich.textSpan! as TextSpan;
      expect((span.children!.first as TextSpan).style?.fontSize,
          AppFontSize.metricHero);
      expect((span.children!.first as TextSpan).style?.color, Colors.white);
      // 单位默认取数字色 70% 透明度。
      expect(
        (span.children![1] as TextSpan).style?.color,
        Colors.white.withValues(alpha: 0.7),
      );
    });
  });

  group('AppProgressRing', () {
    testWidgets('默认显示百分比，越界值被裁剪', (tester) async {
      await tester.pumpWidget(_host(const AppProgressRing(value: 0.65)));
      expect(find.text('65%'), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        0.65,
      );

      await tester.pumpWidget(_host(const AppProgressRing(value: 1.5)));
      expect(find.text('100%'), findsOneWidget);

      await tester.pumpWidget(_host(const AppProgressRing(value: -0.5)));
      expect(find.text('0%'), findsOneWidget);

      await tester.pumpWidget(_host(const AppProgressRing(value: double.nan)));
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('自定义 text 覆盖百分比；size/strokeWidth 生效', (tester) async {
      await tester.pumpWidget(_host(const AppProgressRing(
        value: 0.5,
        size: 64,
        strokeWidth: 6,
        text: '半程',
      )));

      expect(find.text('半程'), findsOneWidget);
      expect(find.text('50%'), findsNothing);

      // 量真正带尺寸的元素：进度环被包在 size×size 的 SizedBox 里，
      // 直接量 AppProgressRing 只会量到父级给的约束尺寸。
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(64, 64),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .strokeWidth,
        6,
      );
    });

    testWidgets('语义标签包含进度', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const AppProgressRing(value: 1.0)));
      expect(find.bySemanticsLabel(RegExp('进度 100%')), findsWidgets);
      handle.dispose();
    });
  });

  group('AppMiniBarChart', () {
    test('weekLabels 为周一到周日', () {
      expect(AppMiniBarChart.weekLabels,
          ['周一', '周二', '周三', '周四', '周五', '周六', '周日']);
    });

    testWidgets('values 为空时渲染空盒子', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(values: [])));

      expect(_inside(AppMiniBarChart, find.byType(Container)), findsNothing);
      expect(_inside(AppMiniBarChart, find.byType(Text)), findsNothing);
    });

    testWidgets('全 0 且提供 empty 时展示替代内容', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [0, 0, 0, 0, 0, 0, 0],
        empty: Text('本周还没有跑量'),
      )));

      expect(find.text('本周还没有跑量'), findsOneWidget);
      expect(_inside(AppMiniBarChart, find.byType(Container)), findsNothing);
    });

    testWidgets('7 根柱子 + 星期标签，今日高亮，未来日画空柱', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [1000, 0, 0, 0, 0, 0, 0],
        highlightIndex: 0,
        minBarHeight: 4,
        maxBarHeight: 44,
      )));

      expect(_inside(AppMiniBarChart, find.byType(Container)), findsNWidgets(7));
      for (final label in AppMiniBarChart.weekLabels) {
        expect(find.text(label), findsOneWidget);
      }

      // 今日：高亮色 + 满高。
      final active = _barsWithColor(AppColors.accentHot);
      expect(active, findsOneWidget);
      expect(tester.getSize(active).height, closeTo(44, 1e-9));

      // 其余 6 天视为未来日：空柱色 + 最小高度。
      final future = _barsWithColor(AppColors.barEmpty);
      expect(future, findsNWidgets(6));
      expect(tester.getSize(future.first).height, closeTo(4, 1e-9));

      final today = tester.widget<Text>(find.text('周一'));
      expect(today.style?.fontWeight, AppFontWeight.bold);
      expect(today.style?.color, AppColors.accentHot);
      final tomorrow = tester.widget<Text>(find.text('周二'));
      expect(tomorrow.style?.fontWeight, AppFontWeight.medium);
      expect(tomorrow.style?.color, AppColors.textHint);
    });

    testWidgets('已过且有值的柱子按比例取高，颜色为 barPast', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [500, 1000, 0, 0],
        highlightIndex: 3,
        minBarHeight: 4,
        maxBarHeight: 44,
      )));

      final past = _barsWithColor(AppColors.barPast);
      expect(past, findsNWidgets(2));
      expect(tester.getSize(past.first).height, closeTo(24, 1e-9));
      expect(tester.getSize(past.last).height, closeTo(44, 1e-9));
      // 周一/周二已过；周三值为 0 且非未来日 → 空柱色；周四为今日高亮。
      expect(_barsWithColor(AppColors.barEmpty), findsOneWidget);
      expect(tester.getSize(_barsWithColor(AppColors.barEmpty)).height,
          closeTo(4, 1e-9));
      expect(_barsWithColor(AppColors.accentHot), findsOneWidget);
    });

    testWidgets('maxValue 显式给定可稳定柱高比例', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [10],
        maxValue: 100,
        minBarHeight: 4,
        maxBarHeight: 44,
      )));

      expect(
        tester.getSize(_barsWithColor(AppColors.barPast).first).height,
        closeTo(8, 1e-9),
      );
    });

    testWidgets('负值按 0 处理', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [-5],
        minBarHeight: 4,
        maxBarHeight: 44,
      )));

      expect(_barsWithColor(AppColors.barEmpty), findsOneWidget);
      expect(tester.getSize(_barsWithColor(AppColors.barEmpty)).height,
          closeTo(4, 1e-9));
      expect(_barsWithColor(AppColors.barPast), findsNothing);
    });

    testWidgets('showLabels 为 false 时不渲染标签；自定义 labels 生效', (tester) async {
      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [1, 2, 3, 4, 5, 6, 7],
        showLabels: false,
      )));
      expect(_inside(AppMiniBarChart, find.byType(Text)), findsNothing);

      await tester.pumpWidget(_host(const AppMiniBarChart(
        values: [1, 2],
        labels: ['一', '二'],
      )));
      expect(find.text('一'), findsOneWidget);
      expect(find.text('二'), findsOneWidget);
    });
  });

  group('AppDeltaChip', () {
    testWidgets('正向：绿底绿字', (tester) async {
      await tester.pumpWidget(_host(const AppDeltaChip(text: '+1.2 km')));

      expect(find.text('+1.2 km'), findsOneWidget);
      final container = tester.widget<Container>(
        _inside(AppDeltaChip, find.byType(Container)).first,
      );
      expect((container.decoration! as BoxDecoration).color,
          AppColors.chipGreenBg);
      expect(tester.widget<Text>(find.text('+1.2 km')).style?.color,
          AppColors.deltaUp);
    });

    testWidgets('负向：红底红字', (tester) async {
      await tester.pumpWidget(
          _host(const AppDeltaChip(text: '-0.8 km', positive: false)));

      final container = tester.widget<Container>(
        _inside(AppDeltaChip, find.byType(Container)).first,
      );
      expect((container.decoration! as BoxDecoration).color,
          AppColors.chipRedBg);
      expect(tester.widget<Text>(find.text('-0.8 km')).style?.color,
          AppColors.danger);
    });

    testWidgets('showIcon 时显示上升/下降箭头，可覆盖配色', (tester) async {
      await tester.pumpWidget(_host(const AppDeltaChip(
        text: '+1.2 km',
        showIcon: true,
      )));
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      await tester.pumpWidget(_host(const AppDeltaChip(
        text: '-0.8 km',
        positive: false,
        showIcon: true,
      )));
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      await tester.pumpWidget(_host(const AppDeltaChip(
        text: '持平',
        background: AppColors.dividerLight,
        foreground: AppColors.textHint,
      )));
      final container = tester.widget<Container>(
        _inside(AppDeltaChip, find.byType(Container)).first,
      );
      expect((container.decoration! as BoxDecoration).color,
          AppColors.dividerLight);
      expect(tester.widget<Text>(find.text('持平')).style?.color,
          AppColors.textHint);
    });
  });

  group('AppDashboardCard', () {
    testWidgets('无渐变时复用 AppCard', (tester) async {
      await tester.pumpWidget(
          _host(const AppDashboardCard(child: Text('白卡'))));

      expect(find.text('白卡'), findsOneWidget);
      expect(_inside(AppDashboardCard, find.byType(AppCard)), findsOneWidget);
    });

    testWidgets('渐变卡：圆角 24 + 渐变 + 可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppDashboardCard(
        gradientColors: AppColors.heroGradient,
        radius: AppRadius.lg,
        onTap: () => taps++,
        child: const Text('今日目标'),
      )));

      expect(_inside(AppDashboardCard, find.byType(AppCard)), findsNothing);
      final container = tester.widget<Container>(
        _inside(AppDashboardCard, find.byType(Container)).first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.gradient, isNotNull);
      expect(decoration.gradient!.colors, AppColors.heroGradient);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.lg));

      await tester.tap(find.text('今日目标'));
      expect(taps, 1);
    });
  });

  group('UserAvatar', () {
    testWidgets('无昵称时显示问号，尺寸可配', (tester) async {
      await tester.pumpWidget(_host(const UserAvatar(size: 60)));

      expect(find.text('?'), findsOneWidget);
      expect(
        tester.getSize(_inside(UserAvatar, find.byType(Container)).first),
        const Size(60, 60),
      );
    });

    testWidgets('取昵称首字（emoji 按字素簇）', (tester) async {
      await tester.pumpWidget(_host(const UserAvatar(nickname: '张三')));
      expect(find.text('张'), findsOneWidget);

      await tester.pumpWidget(_host(const UserAvatar(nickname: '😀abc')));
      expect(find.text('😀'), findsOneWidget);
    });

    testWidgets('avatarUrl 为空串时走首字兜底', (tester) async {
      await tester.pumpWidget(
          _host(const UserAvatar(nickname: '李四', avatarUrl: '')));

      expect(find.text('李'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('ScrollableCenter', () {
    testWidgets('包裹内容并可滚动（AlwaysScrollable 物理）', (tester) async {
      await tester.pumpWidget(_host(const ScrollableCenter(
        child: Text('空态内容'),
      )));

      expect(find.text('空态内容'), findsOneWidget);
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());

      // 外层给的是 390×600 的固定盒子（flutter_test 默认画布 800×600），
      // ScrollableCenter 会撑满它，并把 minHeight 设为可用高度以保证可下拉。
      expect(
        tester.getSize(find.byType(ScrollableCenter)),
        const Size(390, 600),
      );
      final constrained = tester.widget<ConstrainedBox>(
        find.descendant(
          of: find.byType(ScrollableCenter),
          matching: find.byType(ConstrainedBox),
        ),
      );
      expect(constrained.constraints.minHeight, 600);
    });
  });
}
