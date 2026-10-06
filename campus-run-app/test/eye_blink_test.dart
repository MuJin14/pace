import 'package:campus_run_app/core/widgets/auth_scaffold.dart';
import 'package:campus_run_app/features/auth/pages/login_page.dart';
import 'package:campus_run_app/features/auth/pages/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「闭眼」交互的状态验证。
///
/// **设计意图**（用户提出）：跑道上的圆点与上方弧线组成一只眼睛；
/// 用户输入密码时圆点垂直压扁成一条横线 = **闭眼**，
/// 表达「密码是安全的，没人看着」。
///
/// 这里断言的是**状态联动是否正确**（聚焦密码 → eyeClosed 变为 true），
/// 而不是像素长什么样 —— 后者靠人工看截图确认。
/// 之所以要自动化：焦点 → 状态 → 背景 这条链路有三层，
/// 任何一层漏接都不会报错，只会「看起来没反应」，很难发现。
void main() {
  /// 当前背景的闭眼状态。
  bool eyeClosedOf(WidgetTester tester) {
    final w = tester.widget<RunningTrackBackdrop>(
      find.byType(RunningTrackBackdrop),
    );
    return w.eyeClosed;
  }

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginPage())),
    );
    await tester.pump();
  }

  Future<void> pumpRegister(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: RegisterPage())),
    );
    await tester.pump();
  }

  /// 按提示文字定位输入框并聚焦。
  Future<void> focusField(WidgetTester tester, String hint) async {
    final field = find.ancestor(
      of: find.text(hint),
      matching: find.byType(TextFormField),
    );
    expect(field, findsOneWidget, reason: '找不到输入框「$hint」');
    await tester.tap(field);
    // ⚠️ 绝对不能用 pumpAndSettle：背景的跑道动画是 `repeat()` 无限循环的，
    //    pumpAndSettle 会一直等「不再有帧在调度」，永远等不到 → 测试超时。
    //    这里只需要推进一帧让 setState 生效即可。
    await tester.pump();
  }

  group('登录页', () {
    testWidgets('初始是「睁眼」（没有输入框被聚焦）', (tester) async {
      await pumpLogin(tester);
      expect(eyeClosedOf(tester), isFalse);
    });

    testWidgets('聚焦密码框 → 闭眼', (tester) async {
      await pumpLogin(tester);
      await focusField(tester, '密码');
      expect(eyeClosedOf(tester), isTrue,
          reason: '输入密码时应当闭眼（表达「没人看着」）');
    });

    testWidgets('聚焦手机号不会闭眼（只有密码才闭眼）', (tester) async {
      await pumpLogin(tester);
      await focusField(tester, '手机号');
      expect(eyeClosedOf(tester), isFalse,
          reason: '手机号不是敏感输入，不该闭眼');
    });

    testWidgets('从密码框切回手机号 → 重新睁眼', (tester) async {
      await pumpLogin(tester);
      await focusField(tester, '密码');
      expect(eyeClosedOf(tester), isTrue);

      await focusField(tester, '手机号');
      expect(eyeClosedOf(tester), isFalse,
          reason: '离开密码框必须恢复睁眼，否则会一直闭着');
    });
  });

  group('注册页', () {
    testWidgets('聚焦密码框 → 闭眼', (tester) async {
      await pumpRegister(tester);
      await focusField(tester, '密码（至少 6 位）');
      expect(eyeClosedOf(tester), isTrue);
    });

    testWidgets('聚焦昵称不会闭眼', (tester) async {
      await pumpRegister(tester);
      await focusField(tester, '昵称');
      expect(eyeClosedOf(tester), isFalse);
    });
  });
}
