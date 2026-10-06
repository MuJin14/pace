import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 打开外部链接。
///
/// 走的是本项目已有的原生通道 `campus_run/platform`（与读取版本号、
/// 查询电池优化同一套），**不引入 url_launcher**。
///
/// ## 为什么不加 url_launcher
///
/// 本项目历史上就吃过「插件没被注册进构建」的亏：`package_info_plus`
/// 在 pubspec 里、也下载了，但 `.flutter-plugins-dependencies` 是陈旧的
/// （构建长期带 `--no-pub`），于是 `PackageInfo.fromPlatform()` 抛
/// `MissingPluginException`，而调用方是静默失败 ——
/// **更新弹窗几个月都没出现过，日志里一个字都没有**。
///
/// 事后补 `pub get` 时又发现 9.0.1 要求 Kotlin 2.x，本项目是 1.8.22，
/// 直接编译不过。所以现在对此类「原生三行就能做完」的能力，
/// 一律走自己的通道，不去赌插件解析状态。
class ExternalLink {
  ExternalLink._();

  static const MethodChannel _channel =
      MethodChannel('campus_run/platform');

  /// 是否是单元测试环境（测试里没有原生实现）。
  ///
  /// ⚠️ 必须显式开关，不能靠 `Platform.isAndroid` 判断 ——
  /// 单元测试跑在宿主平台上，那个表达式恒为 false，
  /// 会让测试**永远走不到真实分支**（这个坑在版本号读取上踩过一次）。
  @visibleForTesting
  static bool? debugForceSupported;

  static bool get isSupported =>
      debugForceSupported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// 用系统浏览器打开 [url]。
  ///
  /// 返回 true 表示已经交给系统。失败返回 false —— 调用方应当给出提示，
  /// 不要静默忽略（否则用户点了没反应，只会以为按钮坏了）。
  static Future<bool> open(String url) async {
    if (url.isEmpty) return false;
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return ok ?? false;
    } on MissingPluginException catch (e) {
      // 明确区分「插件没注册」与「打开失败」：前者是构建问题，必须留痕。
      debugPrint('[链接] 原生通道不可用（构建问题？）: $e');
      return false;
    } catch (e) {
      debugPrint('[链接] 打开失败: $e');
      return false;
    }
  }
}

/// 项目的开源仓库地址。
///
/// 放在这里而不是散落在各处，是为了「只改一个地方」——
/// 仓库名变了（改用户名、改仓库名）不至于漏掉某处文案。
class ProjectLinks {
  ProjectLinks._();

  /// 项目主页（源码）。
  static const String repository = 'https://github.com/MuJin14/pace';

  /// 发行版列表：这里能直接下载到每个版本的 APK。
  ///
  /// 相比「点仓库再找 Releases」，这个入口对用户更直接 ——
  /// 他来这里的目的一般就是要装包。
  static const String releases = '$repository/releases';

  /// 问题反馈。
  static const String issues = '$repository/issues';
}
