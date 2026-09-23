import 'package:flutter/foundation.dart';

/// 全局配置。
///
/// API 基础地址的优先级：`--dart-define=API_BASE_URL=...` 显式覆盖 > 平台默认值。
/// 平台默认：Web(localhost) / Android 模拟器(10.0.2.2) / 其余(localhost)。
/// 真机调试请用 `flutter run --dart-define=API_BASE_URL=http://<局域网IP>:8080`。
class AppConfig {
  AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8080';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }
}
