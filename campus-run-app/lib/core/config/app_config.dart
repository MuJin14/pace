import 'package:flutter/foundation.dart';

/// 全局配置。
///
/// API 基础地址的优先级：`--dart-define=API_BASE_URL=...` 显式覆盖 > 平台默认值。
///
/// **真机 / 模拟器调试**推荐 `adb reverse tcp:8080 tcp:8080`，无需任何额外参数
/// （Android 默认值即为 `127.0.0.1:8080`）。
/// 若走局域网，则显式覆盖：
/// `flutter run --dart-define=API_BASE_URL=http://<局域网IP>:8080`
class AppConfig {
  AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8080';
    if (defaultTargetPlatform == TargetPlatform.android) {
      // ⚠️ 必须写 127.0.0.1，**不能写 localhost** —— 这是实测踩过的坑。
      //
      // 真机通过 `adb reverse` 连后端时，Dart 的 HTTP 客户端解析 `localhost`
      // 会优先走 IPv6（::1），而 `adb reverse` 建立的是 IPv4 隧道，请求发不出去。
      // App 表现为「网络连接失败」卡在启动页（若本地有 token 则连登录页都进不去）。
      //
      // 极易误判：从手机 `curl localhost:8080` 是**通的**（curl 会自动回退到 IPv4），
      // 于是很容易得出"隧道没问题、肯定是代码 bug"的错误结论。
      // 写死 127.0.0.1 直接绕开这个解析差异。
      return 'http://127.0.0.1:8080';
    }
    return 'http://localhost:8080';
  }
}
