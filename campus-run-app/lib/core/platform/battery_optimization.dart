import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 电池优化状态查询 + 跳转系统设置。
///
/// ## 这里**不做**什么（重要）
///
/// 曾经实现过完整的「前台服务保活」方案：App 起一个常驻前台服务维持
/// WebSocket，让退到后台也能及时收到消息。评估后**整体放弃了** ——
///
/// 前台服务**必须**在通知栏常驻一条通知（Android 硬性要求，无法绕过）。
/// 对一个校园跑步 App 来说，为了消息及时性而长期占用用户的通知栏，
/// 属于**强制打扰**，不划算。
///
/// 所以现在只保留最轻的部分：
///   · 查询「是否已被排除在电池优化之外」；
///   · 打开系统的电池优化设置页，**让用户自己决定**。
///
/// 即使不设，App 的所有功能都正常，只是 App 在后台时的消息及时性差一些 ——
/// 消息不会丢（服务端有未读计数，重新打开时会补上）。
class BatteryOptimization {
  BatteryOptimization._();

  static const MethodChannel _channel = MethodChannel('campus_run/platform');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 是否已被排除在电池优化之外。
  ///
  /// ⚠️ 部分国产 ROM 上可能恒为 true（不实现或误报），所以只能把它当作
  /// 「**已知未排除**」的判据：返回 false 一定要提示；
  /// 返回 true 不代表后台就稳。
  static Future<bool> isIgnoringOptimizations() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } catch (e) {
      debugPrint('[电池优化] 查询失败: $e');
      return true;
    }
  }

  /// 打开系统的电池优化设置列表（仅跳转，不申请、不改任何设置）。
  ///
  /// 返回 true 表示已成功跳转。
  static Future<bool> openSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openBatteryOptimizationSettings') ??
          false;
    } catch (e) {
      debugPrint('[电池优化] 打开设置失败: $e');
      return false;
    }
  }
}
