import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 「允许安装未知应用」这个开关的状态与跳转。
///
/// ## 为什么需要它（真实故障）
///
/// 用户反馈：**「下载完了没有弹出安装界面」**。
///
/// 根因有两层：
///
///  1. manifest 里缺 `REQUEST_INSTALL_PACKAGES` —— Android 8.0+ 会
///     **静默拒绝**安装意图：不弹安装界面、也不报错。这就是用户看到的现象。
///
///  2. 即使补上权限，**用户仍可能在系统授权页点「拒绝」**。
///     那时安装同样不会发生，而 `open_filex` 只负责「把意图交出去」，
///     可能仍返回成功 —— 界面一片安静，用户只会觉得「点了没反应」。
///
/// 所以下载完成后要**先查这个开关**：
///   · 没开启 → 明确告诉用户「差一步：需要允许安装」并提供跳转按钮；
///   · 已开启 → 正常唤起安装器。
///
/// 这样把「静默失败」变成「有指引的失败」—— 这类问题的共同特征就是
/// **不报错**，所以必须主动查。
class InstallPermission {
  InstallPermission._();

  static const MethodChannel _channel = MethodChannel('campus_run/platform');

  /// Android 8.0 以下没有「安装未知应用」的按应用开关，视为始终允许。
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 是否已被允许安装应用。
  ///
  /// 查询失败时返回 **true**：宁可让用户直接去试安装（那时系统会给出自己的
  /// 授权页），也不要因为一次查询失败就把用户挡在「请先去设置」的提示前。
  static Future<bool> isAllowed() async {
    if (!_supported) return true;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? true;
    } catch (e) {
      debugPrint('[安装] 查询安装权限失败（按允许处理）: $e');
      return true;
    }
  }

  /// 跳到系统的「安装未知应用」授权页。
  ///
  /// 返回 false 表示所有候选页面都打不开（极少数 ROM）。
  static Future<bool> openSettings() async {
    if (!_supported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openInstallPermissionSettings') ??
          false;
    } catch (e) {
      debugPrint('[安装] 打开安装权限设置失败: $e');
      return false;
    }
  }
}
