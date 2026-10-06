import 'package:campus_run_app/features/profile/pages/privacy_policy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户协议与隐私政策页面的内容与结构检查。
///
/// **为什么需要**：
///   · 协议正文里用 `**粗体**` 标注重点，之前被当纯字符串渲染，
///     页面上出现字面星号 —— 看起来像没写完的草稿；
///   · 联系方式必须是**真实可达**的邮箱，写占位地址等于让
///     「查阅/更正/删除权」这些承诺落空；
///   · 章节增删后必须重排序号，否则会出现「七、八、九」里缺一节
///     却还留着「九」这种明显没维护好的痕迹。
///
/// ⚠️ 取文本时**不能**直接用 `find.byType(Text)` ——
/// `RichText` 也是 `Text` 的子类，`widgetList<Text>` 会把
/// `_RichBody` 内部的 `RichText` 也算进来，导致：
///   · 断言「页面上没有字面星号」时拿到的是渲染前的原始串；
///   · 断言徽章数字时被正文里同名的数字干扰。
/// 所以这里用 `text.data != null` 只取真正的 `Text`。
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));
    await tester.pumpAndSettle();
  }

  /// 页面上所有**真正的 Text** 的内容（不含 RichText）。
  List<String> plainTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .where((t) => t.data != null)
      .map((t) => t.data!)
      .toList();

  /// 滚动遍历整个列表，收集沿途出现的所有纯 Text。
  ///
  /// ⚠️ 必须滚动：正文用 `ListView` 承载，而它是**懒加载**的 ——
  /// 屏幕外的章节根本不会被构建。直接断言「页面上有第 8 节」
  /// 只会拿到可见的前几条，测试假失败（第一版就栽在这里）。
  Future<List<String>> scrollAllTexts(WidgetTester tester) async {
    final collected = <String>{};
    final list = find.byType(Scrollable);
    expect(list, findsWidgets, reason: '页面应当是可滚动的');

    for (var i = 0; i < 30; i++) {
      collected.addAll(plainTexts(tester));
      final before = tester.getTopLeft(find.byType(Scrollable).first).dy;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.byType(Scrollable).first).dy;
      // 位置没变说明已经到底
      if ((before - after).abs() < 0.5) break;
    }
    collected.addAll(plainTexts(tester));
    return collected.toList();
  }

  /// 页面全部可见文字，包含 RichText 里富文本的纯文本部分。
  String allVisibleText(WidgetTester tester, List<String> texts) {
    final buf = StringBuffer();
    for (final t in texts) {
      buf.writeln(t);
    }
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) buf.write(span.text);
        return true;
      });
      buf.writeln();
    }
    return buf.toString();
  }

  testWidgets('正文不残留字面的 ** 标记', (tester) async {
    await pump(tester);
    final texts = await scrollAllTexts(tester);

    final bad = texts.where((t) => t.contains('**')).toList();
    expect(bad, isEmpty,
        reason: '这些文本仍含字面星号，说明 ** 没有被解析：$bad');
  });

  testWidgets('关键合规表述被渲染成粗体（不是普通字重）', (tester) async {
    await pump(tester);

    var foundBold = false;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((span) {
        if (span is TextSpan &&
            (span.text ?? '').contains('你主动点击') &&
            span.style?.fontWeight == FontWeight.w700) {
          foundBold = true;
        }
        return true;
      });
    }
    expect(foundBold, isTrue,
        reason: '「你主动点击…后才采集定位」是必须突出的合规表述，应当是粗体');
  });

  testWidgets('页面能正常构建（不抛异常）', (tester) async {
    await pump(tester);
    expect(find.text('用户协议与隐私政策'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('联系方式', () {
    testWidgets('使用真实邮箱，且不再出现占位地址', (tester) async {
      await pump(tester);
      final all = allVisibleText(tester, await scrollAllTexts(tester));

      expect(all.contains('support@example.com'), isFalse,
          reason: '不能保留占位邮箱');
      expect(all.contains('mujin019@163.com'), isTrue,
          reason: '应当使用真实可达的联系邮箱');
    });
  });

  group('章节结构', () {
    testWidgets('已删除「信息安全」一节', (tester) async {
      await pump(tester);
      final all = allVisibleText(tester, await scrollAllTexts(tester));

      expect(all.contains('信息安全'), isFalse,
          reason: '该节已按要求删除');
      expect(all.contains('BCrypt'), isFalse,
          reason: '该节内容不该残留');
    });

    testWidgets('序号从 1 连续排到 8，没有缺口也没有多余的 9', (tester) async {
      await pump(tester);
      final texts = await scrollAllTexts(tester);

      for (var n = 1; n <= 8; n++) {
        expect(texts, contains('$n'), reason: '缺少第 $n 节的序号徽章');
      }
      expect(texts, isNot(contains('9')),
          reason: '删掉一节后不该还留 9 —— 说明序号没有重排');
    });

    testWidgets('标题不再带「一、」这类中文序号（序号已由徽章承载）',
        (tester) async {
      await pump(tester);

      const titles = [
        '我们收集哪些信息',
        '定位权限如何使用',
        '信息用于什么目的',
        '我们如何共享信息',
        '数据存储与保留',
        '你的权利',
        '未成年人保护',
        '联系我们',
      ];
      final texts = await scrollAllTexts(tester);
      for (final t in titles) {
        // 标题本身应当存在，且**不带**中文序号前缀
        final matches = texts.where((s) => s.trim() == t).toList();
        expect(matches, isNotEmpty, reason: '找不到标题「$t」（或它仍带序号前缀）');
      }
    });
  });

  testWidgets('顶部信息卡说明生效日期', (tester) async {
    await pump(tester);
    final all = allVisibleText(tester, await scrollAllTexts(tester));

    expect(all.contains('请在使用前仔细阅读'), isTrue);
    expect(all.contains('生效日期'), isTrue);
  });
}
