import 'package:campus_run_app/core/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Validators` 单元测试：只断言具体返回文案，不使用 `isNotNull` 之类弱断言。
void main() {
  group('Validators.validatePhone', () {
    test('合法手机号（含首尾空白）返回 null', () {
      expect(Validators.validatePhone('13800138000'), isNull);
      expect(Validators.validatePhone('19912345678'), isNull);
      expect(Validators.validatePhone(' 13800138000 '), isNull);
      expect(Validators.validatePhone('13800138000\n'), isNull);
      // 各号段首位数都要放行
      for (final second in ['3', '4', '5', '6', '7', '8', '9']) {
        expect(Validators.validatePhone('1${second}800138000'), isNull,
            reason: '1$second 号段应当合法');
      }
    });

    test('号段不合法 → 明确提示号段问题（而不是笼统的「格式不正确」）', () {
      // 真实反馈：用户输入 11111111111，本地只校验了「11 位数字」所以放行，
      // 发到后端才被拒，界面只显示一句「参数错误」，完全看不出原因。
      // 现在本地就挡住，并说清是号段问题。
      expect(Validators.validatePhone('11111111111'), '手机号号段不正确（须以 13–19 开头）');
      expect(Validators.validatePhone('10000000000'), '手机号号段不正确（须以 13–19 开头）');
      expect(Validators.validatePhone('12000000000'), '手机号号段不正确（须以 13–19 开头）');
      expect(Validators.validatePhone('00000000000'), '手机号号段不正确（须以 13–19 开头）');
    });

    test('null / 空串 / 纯空白 → 请输入手机号', () {
      expect(Validators.validatePhone(null), '请输入手机号');
      expect(Validators.validatePhone(''), '请输入手机号');
      expect(Validators.validatePhone('   '), '请输入手机号');
      expect(Validators.validatePhone('\t\n'), '请输入手机号');
    });

    test('位数不对 → 手机号应为 11 位数字', () {
      expect(Validators.validatePhone('1380013800'), '手机号应为 11 位数字'); // 10 位
      expect(Validators.validatePhone('138001380001'), '手机号应为 11 位数字'); // 12 位
      expect(Validators.validatePhone('1'), '手机号应为 11 位数字');
    });

    test('非数字字符 / 带区号 / 带分隔符 → 手机号应为 11 位数字', () {
      expect(Validators.validatePhone('1380013800a'), '手机号应为 11 位数字');
      expect(Validators.validatePhone('+8613800138000'), '手机号应为 11 位数字');
      expect(Validators.validatePhone('138 0013 8000'), '手机号应为 11 位数字');
      expect(Validators.validatePhone('138-0013-8000'), '手机号应为 11 位数字');
      expect(Validators.validatePhone('１３８００１３８０００'), '手机号应为 11 位数字');
    });

    test('超长输入不抛异常，直接判为位数不对', () {
      final tooLong = List<String>.filled(4096, '1').join();
      expect(Validators.validatePhone(tooLong), '手机号应为 11 位数字');
    });
  });

  group('Validators.validatePassword', () {
    test('null / 空串 → 请输入密码', () {
      expect(Validators.validatePassword(null), '请输入密码');
      expect(Validators.validatePassword(''), '请输入密码');
    });

    test('少于 6 位 → 密码至少 6 位', () {
      expect(Validators.validatePassword('1'), '密码至少 6 位');
      expect(Validators.validatePassword('12345'), '密码至少 6 位');
      expect(Validators.validatePassword('   '), '密码至少 6 位');
    });

    test('恰好 6 位及以上返回 null', () {
      expect(Validators.validatePassword('123456'), isNull);
      expect(Validators.validatePassword('12345 '), isNull);
      expect(Validators.validatePassword('secret123'), isNull);
    });

    test('长度按 UTF-16 代码单元计算（emoji 占 2）', () {
      expect(Validators.validatePassword('😀😀😀'), isNull); // 6 个代码单元
      expect(Validators.validatePassword('😀😀'), '密码至少 6 位'); // 4 个代码单元
    });

    test('超过 32 位 → 密码最长 32 位（与后端 @Size(max=32) 对齐）', () {
      // 本地不挡的话，用户会打完之后才被后端拒绝，且提示只有一句「参数错误」。
      expect(Validators.validatePassword('a' * 32), isNull, reason: '恰好 32 位合法');
      expect(Validators.validatePassword('a' * 33), '密码最长 32 位');
      final tooLong = List<String>.filled(10000, 'a').join();
      expect(Validators.validatePassword(tooLong), '密码最长 32 位');
    });

    test('不做 trim：6 个空格视为合法（现状记录）', () {
      // 与 validatePhone 不同，validatePassword 直接取原始长度；
      // 该行为已作为疑似缺陷写入测试报告，此处锁定现状。
      expect(Validators.validatePassword('      '), isNull);
    });
  });

  group('Validators.validateNickname', () {
    test('null / 空串 / 纯空白 → 请输入昵称', () {
      expect(Validators.validateNickname(null), '请输入昵称');
      expect(Validators.validateNickname(''), '请输入昵称');
      expect(Validators.validateNickname('   '), '请输入昵称');
      expect(Validators.validateNickname('\n\t'), '请输入昵称');
    });

    test('任意非空内容通过', () {
      expect(Validators.validateNickname('a'), isNull);
      expect(Validators.validateNickname('张三'), isNull);
      expect(Validators.validateNickname(' 张三 '), isNull);
    });

    test('超过 30 字 → 昵称最长 30 个字符（与后端 @Size(max=30) 对齐）', () {
      // 原来本地没有上限，用户能打完 100 个字再被后端拒绝，
      // 而且提示只有一句「参数错误」。现在本地就给出准确原因。
      expect(Validators.validateNickname('名' * 30), isNull, reason: '恰好 30 字合法');
      expect(Validators.validateNickname('名' * 31), '昵称最长 30 个字符');
      final tooLong = List<String>.filled(512, '名').join();
      expect(Validators.validateNickname(tooLong), '昵称最长 30 个字符');
    });
  });
}
