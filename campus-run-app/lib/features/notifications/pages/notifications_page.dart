import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/update/pending_update_provider.dart';
import '../../../core/widgets/update_dialog.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../badges/providers/badge_provider.dart';
import '../../friends/providers/friend_badge_provider.dart';
import '../../friends/providers/friend_provider.dart';
import '../../goals/providers/goal_provider.dart';
import '../providers/notifications_provider.dart';

/// 通知页：前端聚合展示「好友申请 / 未读消息 / 勋章 / 目标达成」四类通知。
///
/// 数据全部来自既有 provider（见 [notificationsProvider]），不新增后端接口；
/// 复用 AppCard / AppSectionTitle / AppEmptyHint，无数据时展示空态而非空白。
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () =>
                  ref.read(friendBadgeProvider.notifier).clearMessage(),
              child: const Text(
                '全部已读',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: AppFontWeight.medium,
                  color: AppColors.accentHot,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: items.isEmpty
            ? _emptyBody(context)
            : _notificationList(context, items),
      ),
    );
  }

  /// 下拉刷新：重新拉取三个数据源；失败时不打断 UI（错误态由各页面自行处理）。
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(friendRequestsProvider);
    ref.invalidate(badgeMineProvider);
    ref.invalidate(goalListProvider);
    try {
      await Future.wait([
        ref.read(friendRequestsProvider.future),
        ref.read(badgeMineProvider.future),
        ref.read(goalListProvider.future),
      ]);
    } catch (_) {
      // 忽略刷新异常：保留已有数据，避免红点状态被清空
    }
  }

  /// 空态：召唤语 + 一个可点击动作（设计稿 §3 硬性要求）。
  Widget _emptyBody(BuildContext context) {
    return ScrollableCenter(
      child: AppEmptyHint(
        icon: Icons.notifications_none,
        iconBoxSize: 88,
        iconSize: 40,
        iconColor: AppColors.accentHot,
        iconBackground: AppColors.iconBgPeach,
        title: '暂无新通知',
        description: '好友申请、未读消息与勋章达成都会在这里提醒你',
        actionLabel: '去社区看看',
        onAction: () => context.go('/friends'),
        padding: const EdgeInsets.all(AppSpacing.xl),
      ),
    );
  }

  Widget _notificationList(BuildContext context, List<AppNotification> items) {
    // 按固定顺序分组，空分组不渲染
    final groups = <_NotificationGroup>[];
    for (final type in AppNotificationType.values) {
      final groupItems = items.where((n) => n.type == type).toList();
      if (groupItems.isEmpty) continue;
      groups.add(_NotificationGroup(type: type, items: groupItems));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageWide,
        AppSpacing.sm,
        AppSpacing.pageWide,
        AppSpacing.lg,
      ),
      children: [
        for (final group in groups) ...[
          AppSectionTitle(title: group.title),
          const SizedBox(height: AppSpacing.smLg),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.dividerLight,
                    ),
                  _NotificationTile(item: group.items[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.block),
        ],
      ],
    );
  }
}

/// 通知分组（标题由类型推导）。
class _NotificationGroup {
  const _NotificationGroup({required this.type, required this.items});

  final AppNotificationType type;
  final List<AppNotification> items;

  String get title => switch (type) {
        AppNotificationType.appUpdate => '版本更新',
        AppNotificationType.friendRequest => '好友申请',
        AppNotificationType.unreadMessage => '未读消息',
        AppNotificationType.badgeEarned => '勋章',
        AppNotificationType.goalAchieved => '目标达成',
      };
}

/// 单条通知：图标 + 标题 + 说明 + 时间，点击跳转对应页面。
class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  /// 点「发现新版本」时的动作：就地弹更新对话框。
  ///
  /// ⚠️ 这里**不复用** app.dart 里那份弹窗代码，而是直接调 UpdateDialog ——
  /// 因为那边的入口是「启动检查」和「强制更新」，与本条通知的语义不同。
  /// 两边共享同一个 [_updateDialogOpen] 之外的防护靠 UpdateDialog 自身：
  /// 它在关闭前不会重复打开（`show` 内部用 barrierDismissible=false
  /// 且同一时刻只会有一个 route）。
  Future<void> _openUpdate(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(pendingUpdateProvider);
    if (pending == null) return;
    await UpdateDialog.show(context, pending.info, force: pending.mandatory);
  }

  IconData get _icon => switch (item.type) {
        AppNotificationType.appUpdate => Icons.system_update_alt,
        AppNotificationType.friendRequest => Icons.person_add_alt_1,
        AppNotificationType.unreadMessage => Icons.chat_bubble_outline,
        AppNotificationType.badgeEarned => Icons.military_tech,
        AppNotificationType.goalAchieved => Icons.flag_outlined,
      };

  Color get _iconColor => switch (item.type) {
        // 用主色（品牌橙）而不是某个状态色：更新是「建议做的事」，
        // 不是错误也不是成就，用 danger/success 都会误导。
        AppNotificationType.appUpdate => AppColors.primary,
        AppNotificationType.friendRequest => AppColors.accentHot,
        AppNotificationType.unreadMessage => AppColors.secondary,
        AppNotificationType.badgeEarned => AppColors.medal,
        AppNotificationType.goalAchieved => AppColors.deltaUp,
      };

  Color get _iconBackground => switch (item.type) {
        AppNotificationType.appUpdate => AppColors.primaryLight,
        AppNotificationType.friendRequest => AppColors.iconBgPeach,
        AppNotificationType.unreadMessage => AppColors.secondaryLight,
        AppNotificationType.badgeEarned => AppColors.iconBgWarm,
        AppNotificationType.goalAchieved => AppColors.chipGreenBg,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 更新条目没有 route（它不是"跳到某页"），而是就地弹对话框。
    final isUpdate = item.type == AppNotificationType.appUpdate;
    return InkWell(
      onTap: isUpdate
          ? () => _openUpdate(context, ref)
          : (item.route == null ? null : () => context.go(item.route!)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.gap14,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _iconBackground,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(_icon, size: 18, color: _iconColor),
            ),
            const SizedBox(width: AppSpacing.smLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.labelLg,
                      fontWeight: AppFontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (item.description != null &&
                      item.description!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      item.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.hint,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (item.time != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      Formatters.dateTime(item.time),
                      style: const TextStyle(
                        fontSize: AppFontSize.hint,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
