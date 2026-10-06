import 'package:campus_run_app/core/platform/app_version.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 原生版本号桥。
///
/// ## 为什么这个文件必须存在
///
/// 这里出过一次**极难发现**的线上故障：
///
/// > `package_info_plus` 在 pubspec 里、也装了下来，但从未被注册进
/// > Android 构建（`.flutter-plugins-dependencies` 停在旧版本，因为构建
/// > 一直带 `--no-pub` 跳过 `pub get`）。于是 `PackageInfo.fromPlatform()`
/// > 每次都抛 `MissingPluginException`，而上游两处**都是静默失败** ——
/// > **更新弹窗从未出现过，日志里一个字都没有。**
///
/// 而当时所有测试都是绿的，因为测试里 `PackageInfo` 是 mock 的 ——
/// **恰好绕过了故障点**。
///
/// 所以这里的测试要守住两件事：
///   1. 解析逻辑正确（尤其是 `1.9.3+37` 必须剥掉构建号）；
///   2. **失败时不崩、返回空串** —— 那正是当年缺失的一环。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('campus_run/platform');

  /// 让原生返回 [returns]；[throws] 为 true 时模拟 channel 不可用。
  void mockNative(String? returns, {bool throws = false}) {
    // 测试跑在宿主平台上，Platform.isAndroid 恒为 false，会把 read() 短路掉、
    // 根本不走 channel。必须显式打开，否则这些用例测的是「空实现」。
    AppVersion.debugForceSupported = true;
    AppVersion.resetCacheForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'appVersion') return null;
      if (throws) throw MissingPluginException('模拟插件缺失');
      return returns;
    });
  }

  tearDown(() {
    AppVersion.debugForceSupported = null;
    AppVersion.resetCacheForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('版本号解析', () {
    test('剥掉构建号：1.9.3+37 -> 1.9.3', () async {
      mockNative('1.9.3+37');
      // 保留 "+37" 会让版本比较函数解析第三段失败（它按 "." 切分、
      // 取每段的数字前缀），结果是「明明有新版本却不提示」。
      expect(await AppVersion.read(), '1.9.3');
    });

    test('没有构建号时原样返回', () async {
      mockNative('2.0.0');
      expect(await AppVersion.read(), '2.0.0');
    });

    test('多余空白被去掉', () async {
      mockNative('  1.8.0  ');
      expect(await AppVersion.read(), '1.8.0');
    });

    test('原生返回空串时得到空串（调用方据此安全跳过更新检查）', () async {
      mockNative('');
      expect(await AppVersion.read(), '');
    });

    test('原生返回 null 时得到空串', () async {
      mockNative(null);
      expect(await AppVersion.read(), '');
    });

    test('channel 抛异常时**不崩**，返回空串', () async {
      // 这正是当年的故障形态：插件缺失 -> MissingPluginException。
      // 要求是「不崩 + 返回空串」，而不是把异常抛到 UI 层。
      mockNative(null, throws: true);
      expect(await AppVersion.read(), '');
    });
  });

  test('结果被缓存：第二次不再询问原生', () async {
    AppVersion.debugForceSupported = true;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'appVersion') {
        calls++;
        return '1.9.3+37';
      }
      return null;
    });
    AppVersion.resetCacheForTest();

    final first = await AppVersion.read();
    final second = await AppVersion.read();

    expect(first, '1.9.3');
    expect(second, '1.9.3');
    expect(calls, 1, reason: '版本号在 App 生命周期内不变，不该重复询问原生');
  });
}
