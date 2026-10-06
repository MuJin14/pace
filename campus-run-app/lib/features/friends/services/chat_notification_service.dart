import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// 新消息的系统通知 + 震动。
///
/// **职责边界**：本类只负责「怎么提醒」，不负责「该不该提醒」——
/// 后者是 [decideNotifyAction] 纯函数的职责。这样提醒规则可以脱离插件单测。
///
/// 关键设计：
/// - **所有插件调用都 swallow 异常**：通知失败绝不能影响消息接收与红点。
///   通知是锦上添花，消息本身才是主链路。
/// - **不申请权限也不阻止流程**：Android 13+ 需要 POST_NOTIFICATIONS 运行时授权；
///   用户拒绝时只是没有通知，红点仍然工作。
class ChatNotificationService {
  ChatNotificationService._();

  static final ChatNotificationService instance = ChatNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Android 通知渠道 id / 名称。
  static const _channelId = 'campus_run_message';
  static const _channelName = '聊天消息';
  static const _channelDesc = '好友发来的新消息提醒';

  /// 初始化插件。幂等，可重复调用。
  ///
  /// 必须在 `runApp` 之前或第一帧后尽早调用；失败不影响 App 启动。
  Future<void> init() async {
    if (_initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        // 权限在首次真正要发通知时再申请，启动时不打扰用户
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[通知] 初始化失败（不影响消息接收）: $e');
    }
  }

  /// 申请通知权限（Android 13+ / iOS）。
  ///
  /// 建议在**用户进入聊天相关页面**时调用，而不是启动时 ——
  /// 启动时弹权限框，用户还不知道 App 要干什么，拒绝率更高。
  Future<void> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('[通知] 申请权限失败: $e');
    }
  }

  /// 弹一条新消息通知（并震动）。
  ///
  /// @param conversationKey 用发送方 id 作为通知 id：同一好友的多条消息
  ///        会覆盖同一条通知，而不是堆满通知栏。
  Future<void> showMessage({
    required int senderId,
    required String title,
    required String body,
    bool vibrate = true,
  }) async {
    if (vibrate) {
      await vibrateOnce();
    }
    if (!_initialized) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        // 震动已由 Vibration 包负责，避免「震两次」
        enableVibration: false,
        category: AndroidNotificationCategory.message,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      await _plugin.show(
        senderId,
        title,
        body,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      debugPrint('[通知] 弹出失败: $e');
    }
  }

  /// 震一下。
  ///
  /// 分两层，因为不同设备能力差异很大：
  /// 1. 首选 `Vibration` 包（可控时长、可检测是否有马达）；
  /// 2. 没有马达（模拟器 / 部分平板）时退回 `HapticFeedback`，
  ///    至少给触觉反馈而不是完全静默。
  Future<void> vibrateOnce() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          await Vibration.vibrate(duration: 200);
          return;
        }
      }
    } catch (e) {
      debugPrint('[通知] 震动失败，退回触觉反馈: $e');
    }
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // 连触觉反馈都没有（如 Web）：静默忽略
    }
  }

  /// 清掉某会话的通知（用户点进聊天页后）。
  Future<void> cancelFor(int senderId) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(senderId);
    } catch (e) {
      debugPrint('[通知] 清除通知失败: $e');
    }
  }
}
