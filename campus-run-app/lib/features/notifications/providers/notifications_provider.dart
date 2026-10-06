import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/update/pending_update_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/friend_request.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/user_badge.dart';
import '../../badges/providers/badge_provider.dart';
import '../../friends/providers/friend_badge_provider.dart';
import '../../friends/providers/friend_provider.dart';
import '../../goals/providers/goal_provider.dart';

/// 通知类型。
///
/// 顺序即**通知页里的分组顺序**（见 notifications_page 的 `_notificationList`），
/// 所以 [appUpdate] 放在最前 —— 有新版本时它应当是最先看到的一条。
enum AppNotificationType {
  /// 发现新版本。点这一条才会弹更新对话框（见 PendingUpdate 的说明）。
  appUpdate,
  friendRequest,
  unreadMessage,
  badgeEarned,
  goalAchieved,
}

/// 前端聚合的通知条目。
///
/// 不新增后端接口与三方依赖：全部由既有 provider（好友申请、聊天红点、
/// 我的勋章、运动目标）在前端派生，详见 [notificationsProvider]。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.time,
    this.route,
  });

  /// 稳定 id（列表 key / 去重用）
  final String id;

  final AppNotificationType type;

  /// 通知标题（一句话说清发生了什么）
  final String title;

  /// 一行说明，可为空
  final String? description;

  /// 后端原始时间串，展示时用 [Formatters.dateTime]
  final String? time;

  /// 点击后跳转的 go_router 路径
  final String? route;
}

/// 近 7 天才推送「获得勋章」通知，避免历史勋章长期占满通知页与常亮红点。
const int _kBadgeNoticeDays = 7;

/// 勋章通知最多展示条数。
const int _kMaxBadgeNotices = 3;

/// 通知聚合源：好友申请 + 未读聊天消息 + 近 7 天勋章 + 已达成目标。
final notificationsProvider = Provider<List<AppNotification>>((ref) {
  final items = <AppNotification>[];

  // 0. 发现新版本
  //
  // 放在最前：它是唯一一条「点了会改变 App 本身」的通知，
  // 重要性高于其余内容型提醒。
  //
  // 为什么走通知而不是启动弹窗：见 PendingUpdate 的类注释 ——
  // 冷启动弹窗既打扰、又容易被条件反射地点「稍后」而彻底失效。
  final pending = ref.watch(pendingUpdateProvider);
  if (pending != null) {
    items.add(
      AppNotification(
        id: 'app-update-${pending.latest}',
        type: AppNotificationType.appUpdate,
        title: pending.mandatory
            ? '必须更新到 ${pending.latest}'
            : '发现新版本 ${pending.latest}',
        description: pending.mandatory
            ? '当前版本已不再受支持，请立即更新'
            : '点击查看更新内容并安装',
        // route 为 null：这一条不是"跳转到某页"，而是就地弹更新对话框。
        // 具体动作由 _NotificationTile 按 type 决定。
      ),
    );
  }

  // 1. 好友申请（WebSocket 推送会 invalidate friendRequestsProvider）
  final requests =
      ref.watch(friendRequestsProvider).value ?? const <FriendRequest>[];
  for (final r in requests) {
    items.add(
      AppNotification(
        id: 'friend-request-${r.requestId}',
        type: AppNotificationType.friendRequest,
        title: '${r.nickname} 请求加你为好友',
        description: Formatters.uniqueId(r.uniqueId),
        time: r.createdAt,
        route: '/friends',
      ),
    );
  }

  // 2. 未读聊天消息（客户端红点状态，后端暂无未读数接口）
  if (ref.watch(friendBadgeProvider).hasUnreadMessage) {
    items.add(
      const AppNotification(
        id: 'unread-message',
        type: AppNotificationType.unreadMessage,
        title: '你有未读的聊天消息',
        description: '去社区看看好友发来的消息',
        route: '/friends',
      ),
    );
  }

  // 3. 近 7 天获得的勋章（按授予时间倒序，最多 3 条）
  final badges = ref.watch(badgeMineProvider).value ?? const <UserBadge>[];
  final cutoff = DateTime.now().subtract(const Duration(days: _kBadgeNoticeDays));
  final recentBadges = badges.where((b) {
    final dt = DateTime.tryParse(b.awardedAt ?? '');
    // 无授予时间的勋章按「近期」处理，避免漏提醒
    return dt == null || !dt.isBefore(cutoff);
  }).toList()
    ..sort((a, b) => (b.awardedAt ?? '').compareTo(a.awardedAt ?? ''));
  for (final b in recentBadges.take(_kMaxBadgeNotices)) {
    items.add(
      AppNotification(
        id: 'badge-${b.badgeId}',
        type: AppNotificationType.badgeEarned,
        title: '获得勋章「${b.name}」',
        description: b.description,
        time: b.awardedAt,
        route: '/badges',
      ),
    );
  }

  // 4. 已达成目标（进度 100% 或后端标记已完成）
  final goals = ref.watch(goalListProvider).value ?? const <Goal>[];
  for (final g in goals) {
    if (g.progress < 1 && g.status != 1) continue;
    items.add(
      AppNotification(
        id: 'goal-${g.id}',
        type: AppNotificationType.goalAchieved,
        title: '目标已达成',
        description:
            '${_periodLabel(g.periodType)}目标 ${Formatters.distance(g.targetDistanceMeters)} 已完成',
        time: g.endDate ?? g.createdAt,
        route: '/goals',
      ),
    );
  }

  return items;
});

/// 通知条数（红点数量）。
final notificationUnreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).length,
);

/// 是否有通知：首页顶栏铃铛与底部「社区」Tab 红点统一用这个。
final hasNotificationsProvider = Provider<bool>(
  (ref) => ref.watch(notificationUnreadCountProvider) > 0,
);

String _periodLabel(String periodType) => switch (periodType) {
      'monthly' => '每月',
      'custom' => '自定义',
      _ => '每周',
    };
