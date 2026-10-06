import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 读取本应用的版本号。
///
/// ## 为什么不用 package_info_plus
///
/// 这个项目原本用 `package_info_plus`。它在 pubspec 里、也装了下来，
/// 但**从来没有被注册进 Android 构建** —— `.flutter-plugins-dependencies`
/// 由 `flutter pub get` 生成，而构建一直带 `--no-pub` 跳过它，
/// 那份文件停留在很早以前。于是 `PackageInfo.fromPlatform()` 抛
/// `MissingPluginException`，而上游两处**都是静默失败**：
///
/// > **更新弹窗永远不出现，日志里一个字都没有。**
///
/// 用户反馈「从实装这个功能开始就没见过更新弹窗」，而所有单元测试
/// 都是绿的 —— 因为测试里 `PackageInfo` 是 mock 的，恰好绕过了故障点。
///
/// 补上 `pub get` 后插件确实注册了，但 9.0.1 的 Kotlin 代码要求
/// Kotlin 2.x，本项目是 1.8.22，直接编译失败；升级 Kotlin 会牵动整个
/// Gradle 构建，风险远大于收益。
///
/// 而这里要做的事只是读一个字符串，原生三行就够（见 MainActivity.appVersion）。
/// 顺带也去掉了构建期对「插件解析状态」的隐式依赖 —— 那种依赖一旦断裂
/// 就是这样一声不响。
class AppVersion {
  AppVersion._();

  static const MethodChannel _channel = MethodChannel('campus_run/platform');

  /// 缓存的版本号。App 生命周期内不会变，只读一次。
  static String? _cached;

  /// 测试用的平台覆盖。
  ///
  /// `Platform.isAndroid` 在单元测试里恒为 false（测试跑在宿主平台上），
  /// 会把 [read] 直接短路成空串、**根本不碰 channel** ——
  /// 于是「解析逻辑」和「缓存」这两件事在测试里从未被真正执行。
  ///
  /// 这正是本项目栽过的那个坑的同一形态：**测试绕过了真正的代码路径**。
  /// 所以留一个显式开关，让测试能走到真实分支。
  /// 生产环境不要设置它。
  @visibleForTesting
  static bool? debugForceSupported;

  static bool get _isSupported =>
      debugForceSupported ?? (!kIsWeb && Platform.isAndroid);

  /// 本应用版本号，如 `1.9.3`；读不到返回空串。
  ///
  /// **只返回「主.次.补丁」**：构建号（`+37`）对用户没有意义，
  /// 而且版本比较（[isVersionNewer]）只解析点分数字，
  /// 带 `+37` 会让它的第三段解析失败。所以这里统一剥掉。
  static Future<String> read() async {
    if (_cached != null) return _cached!;
    if (!_isSupported) {
      _cached = '';
      return '';
    }
    try {
      final raw = await _channel.invokeMethod<String>('appVersion') ?? '';
      // "1.9.3+37" -> "1.9.3"；没有 "+" 时原样返回
      final plus = raw.indexOf('+');
      _cached = (plus >= 0 ? raw.substring(0, plus) : raw).trim();
      if (_cached!.isEmpty) {
        debugPrint('[版本] ❌ 原生返回空版本号，更新检查将被跳过');
      }
    } catch (e) {
      _cached = '';
      debugPrint('[版本] ❌ 读取版本号失败（MethodChannel），'
          '更新检查将被跳过：$e');
    }
    return _cached!;
  }

  /// 供测试重置缓存。
  @visibleForTesting
  static void resetCacheForTest() {
    _cached = null;
  }
}
