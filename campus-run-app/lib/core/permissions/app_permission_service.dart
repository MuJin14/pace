import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

/// 权限的统一入口：**启动时一次性申请**，而不是等用到才弹。
///
/// ## 为什么改成启动时申请（真实故障）
///
/// 原来的实现把权限申请放在「用到的那个页面」里：
///
/// ```
/// 通知权限  →  chat_page.dart   （进聊天页才申请）
/// 定位权限  →  start_run_page.dart（点「开始跑步」才申请）
/// ```
///
/// 当时的理由是「用户在那个场景下更理解为什么要这个权限，同意率更高」。
/// 但这在**通知权限**上形成了一个死循环：
///
/// ```
/// 不进聊天页 → 拿不到通知权限 → 收不到消息通知
///            → 用户以为「没人给我发消息」→ 更不会进聊天页
/// ```
///
/// 用户反馈的「不进入对话准许发消息前就收不到消息」正是这个现象。
/// **权限是「先有鸡还是先有蛋」问题的典型场景，必须前置。**
///
/// 定位同理：等到点「开始跑步」才要权限，用户已经站在操场上了，
/// 此时拒绝或去设置里翻找，体验最差。
///
/// ## 现在的做法
///
/// 首帧渲染完成后统一申请，并且**先用一张说明卡解释用途再弹系统框**：
/// 直接弹系统权限框时用户不知道 App 要干什么，拒绝率反而更高 ——
/// 前面那个「同意率」的顾虑是对的，解决办法是**先说明再申请**，
/// 而不是把申请推迟到某个页面。
///
/// 说明卡只在「确实缺权限」时出现，且启动 1.2 秒后才弹，
/// 不打断冷启动。
class AppPermissionService {
  AppPermissionService._();

  static final AppPermissionService instance = AppPermissionService._();

  static const String _tag = '[权限]';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _notificationAsked = false;
  bool _locationAsked = false;

  /// 通知权限是否已授予（Android 13+ / iOS；低版本恒为 true）。
  Future<bool> hasNotificationPermission() async {
    if (kIsWeb) return true;
    try {
      if (Platform.isAndroid) {
        final impl = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await impl?.areNotificationsEnabled() ?? true;
      }
      if (Platform.isIOS) {
        // iOS 只能通过请求接口拿到结果；这里用「申请」代替「查询」，
        // 因为 iOS 重复申请已授权时不会再次弹框，是安全操作。
        final impl = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await impl?.requestPermissions(
                alert: true, badge: true, sound: true) ??
            true;
      }
    } catch (e) {
      debugPrint('$_tag 查询通知权限失败（按已授权处理）: $e');
    }
    return true;
  }

  /// 申请通知权限。返回**申请之后**是否可用。
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb) return true;
    _notificationAsked = true;
    try {
      if (Platform.isAndroid) {
        final impl = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await impl?.requestNotificationsPermission();
        // 返回 null 说明系统版本低于 Android 13（没有这个权限），视为可用
        return granted ?? true;
      }
      if (Platform.isIOS) {
        final impl = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await impl?.requestPermissions(
                alert: true, badge: true, sound: true) ??
            true;
      }
    } catch (e) {
      debugPrint('$_tag 申请通知权限失败: $e');
    }
    return false;
  }

  /// 定位权限的当前状态。
  Future<LocationPermission> locationPermission() async {
    if (kIsWeb) return LocationPermission.denied;
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('$_tag 查询定位权限失败: $e');
      return LocationPermission.denied;
    }
  }

  /// 申请**前台**定位权限（不含「始终允许」）。
  ///
  /// ⚠️ 不在这里申请后台定位（「始终允许」）：Android 11+ 要求
  /// 后台定位必须**单独再申请一次**，且系统会把用户带到设置页手动选。
  /// 连着弹两次系统框会被当成骚扰，而且第二次用户往往直接退出。
  /// 后台定位交给「开始跑步」时的引导（那时用户有明确动机去开）。
  Future<LocationPermission> requestLocationPermission() async {
    if (kIsWeb) return LocationPermission.denied;
    _locationAsked = true;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm;
    } catch (e) {
      debugPrint('$_tag 申请定位权限失败: $e');
      return LocationPermission.denied;
    }
  }

  /// 系统「位置信息」总开关是否打开。
  ///
  /// ⚠️ MIUI 上这个方法有**假阴性**（系统定位明明开着却报 false），
  /// 所以只能用来「确认没开」，不能反过来用它判定「已开」——
  /// 真正的判断交给一次真实取点（见 start_run_page 的预热逻辑）。
  Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return false;
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return true;
    }
  }

  /// 是否需要在启动时弹「权限说明卡」。
  ///
  /// 只在**确实缺权限**时才弹：权限都齐了就不打扰。
  Future<PermissionGaps> gaps() async {
    if (kIsWeb) return const PermissionGaps();
    final notif = await hasNotificationPermission();
    final loc = await locationPermission();
    final locationOk =
        loc == LocationPermission.always || loc == LocationPermission.whileInUse;
    return PermissionGaps(
      notification: !notif,
      location: !locationOk,
      locationDeniedForever: loc == LocationPermission.deniedForever,
    );
  }

  /// 本次会话是否已经申请过（避免同一进程内反复弹说明卡）。
  bool get alreadyAsked =>
      _notificationAsked && _locationAsked;
}

/// 缺失的权限项。
@immutable
class PermissionGaps {
  const PermissionGaps({
    this.notification = false,
    this.location = false,
    this.locationDeniedForever = false,
  });

  final bool notification;
  final bool location;

  /// 定位被「拒绝且不再询问」：只能去系统设置里改。
  final bool locationDeniedForever;

  bool get any => notification || location;
}
