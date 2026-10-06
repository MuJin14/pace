import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/friend_item.dart';
import '../../../data/models/friend_request.dart';
import '../../../data/repositories/friend_repository.dart';
import '../providers/friend_badge_provider.dart';
import '../providers/friend_provider.dart';

/// 好友页：待处理申请 + 好友列表。
///
/// 三态：加载中 / 错误（可重试）/ 空态（召唤语 + 可点动作）。
/// 好友申请链路：发送 → 收到 → 接受 / 拒绝 → 列表刷新；
/// 拒绝 = 后端删除 PENDING 记录（不保留 REJECTED，遵循项目约定）。
class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendListProvider);
    final requestsAsync = ref.watch(friendRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('社区'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: '添加好友',
            onPressed: () => context.push('/friends/search'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(friendListProvider);
          ref.invalidate(friendRequestsProvider);
          await Future.wait([
            ref.read(friendListProvider.future),
            ref.read(friendRequestsProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageWide,
            AppSpacing.sm,
            AppSpacing.pageWide,
            AppSpacing.lg,
          ),
          children: [
            _RequestsSection(async: requestsAsync),
            const AppSectionTitle(title: '我的好友'),
            const SizedBox(height: AppSpacing.smLg),
            _FriendsSection(async: friendsAsync),
          ],
        ),
      ),
    );
  }
}

/// 好友申请区块：加载中 / 错误（内联重试，不阻塞好友列表）/ 空（整块隐藏）。
class _RequestsSection extends ConsumerWidget {
  const _RequestsSection({required this.async});

  final AsyncValue<List<FriendRequest>> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (async.isLoading && !async.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.block),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (async.hasError && !async.hasValue) {
      final err = async.error;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.block),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  err is ApiException ? err.message : '好友申请加载失败',
                  style: const TextStyle(
                    fontSize: AppFontSize.body,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(friendRequestsProvider),
                child: const Text(
                  '重试',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final requests = async.value ?? const <FriendRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: AppSectionTitle(title: '好友申请')),
            const SizedBox(width: AppSpacing.sm),
            _CountBadge(count: requests.length),
          ],
        ),
        const SizedBox(height: AppSpacing.smLg),
        ...requests.map((r) => _RequestCard(
              request: r,
              onAccept: () => _act(
                context,
                ref,
                () => ref.read(friendRepositoryProvider).accept(r.requestId),
                '已添加「${r.nickname}」为好友',
              ),
              // 拒绝 = 删除 PENDING 记录，不保留 REJECTED 状态。
              onReject: () => _act(
                context,
                ref,
                () => ref.read(friendRepositoryProvider).reject(r.requestId),
                '已忽略「${r.nickname}」的申请',
              ),
            )),
        const SizedBox(height: AppSpacing.block),
      ],
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String successText,
  ) async {
    try {
      await action();
      ref.invalidate(friendListProvider);
      ref.invalidate(friendRequestsProvider);
      if (context.mounted) _toast(context, successText);
    } on ApiException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }
}

/// 统一 SnackBar 反馈（样式由 AppTheme.snackBarTheme 提供）。
void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: AppFontWeight.bold,
          color: AppColors.onPrimary,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onAccept, required this.onReject});

  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap10),
      padding: const EdgeInsets.all(AppSpacing.gap14),
      child: Row(
        children: [
          UserAvatar(nickname: request.nickname, avatarUrl: request.avatarUrl, size: 46),
          const SizedBox(width: AppSpacing.smLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.nickname,
                  style: const TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  Formatters.uniqueId(request.uniqueId),
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onReject,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.textSecondary.withValues(alpha: 0.1),
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.gap10,
              ),
            ),
            child: const Text('拒绝'),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: onAccept,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.gap10,
              ),
            ),
            child: const Text('接受'),
          ),
        ],
      ),
    );
  }
}

class _FriendsSection extends ConsumerWidget {
  const _FriendsSection({required this.async});

  final AsyncValue<List<FriendItem>> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 本区块嵌在页面的 ListView 内（高度不受限），因此不用 ScrollableCenter 包裹。
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => ErrorState(
        message: err is ApiException ? err.message : '好友列表加载失败，请稍后重试',
        onRetry: () => ref.invalidate(friendListProvider),
      ),
      data: (friends) {
        if (friends.isEmpty) {
          // 区块内空态用 AppEmptyHint（页面级空态才用 EmptyState）。
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: AppEmptyHint(
              icon: Icons.people_outline,
              title: '还没有好友',
              description: '添加同学为好友，一起约跑更容易坚持',
              actionLabel: '去添加好友',
              onAction: () => context.push('/friends/search'),
            ),
          );
        }
        return Column(
          children: friends.map((f) => _FriendItem(
                friend: f,
                onTap: () => context.push(
                  '/chat/${f.userId}',
                  extra: {'name': f.nickname, 'avatarUrl': f.avatarUrl},
                ),
                onDelete: () => _confirmDelete(context, ref, f),
              )).toList(),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, FriendItem f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友「${f.nickname}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(friendRepositoryProvider).delete(f.friendshipId);
      ref.invalidate(friendListProvider);
      if (context.mounted) _toast(context, '已删除好友「${f.nickname}」');
    } on ApiException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }
}

class _FriendItem extends ConsumerWidget {
  const _FriendItem({required this.friend, required this.onTap, required this.onDelete});

  final FriendItem friend;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 订阅「按好友计的未读数」：只有这个好友有未读时，这一行才显示红点。
    // 用 select 只取自己那一项，避免别人来消息时整张列表都重建。
    final unread = ref.watch(
      friendBadgeProvider.select((s) => s.unreadOf(friend.userId)),
    );

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap10),
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: _AvatarWithUnread(
          nickname: friend.nickname,
          avatarUrl: friend.avatarUrl,
          unread: unread,
        ),
        title: Text(
          friend.nickname,
          style: const TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: AppFontWeight.medium,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          // 有未读时副标题换成「N 条新消息」——微信也是这个做法：
          // 用户扫一眼就知道哪一行有事，不必逐行看是谁。
          unread > 0 ? '$unread 条新消息' : Formatters.uniqueId(friend.uniqueId),
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: unread > 0 ? AppColors.primary : AppColors.textSecondary,
            fontWeight: unread > 0 ? AppFontWeight.medium : AppFontWeight.regular,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 数字角标（>99 显示 99+），与头像上的小圆点是两套强度：
            // 小圆点负责「一眼看到哪行」，数字负责「积了多少」。
            if (unread > 0) ...[
              _UnreadCountBadge(count: unread),
              const SizedBox(width: AppSpacing.xs),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textHint),
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('删除好友')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 头像 + 右上角未读小红点。
class _AvatarWithUnread extends StatelessWidget {
  const _AvatarWithUnread({
    required this.nickname,
    required this.avatarUrl,
    required this.unread,
  });

  final String nickname;
  final String? avatarUrl;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final avatar = UserAvatar(nickname: nickname, avatarUrl: avatarUrl, size: 46);
    if (unread <= 0) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
              // 白边让红点在任何头像上都看得清（头像可能是深色的）
              border: Border.all(color: AppColors.card, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// 未读条数角标。
class _UnreadCountBadge extends StatelessWidget {
  const _UnreadCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // 超过 99 收敛成 99+：数字再长会把昵称挤没
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gap6,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: AppFontWeight.bold,
          color: AppColors.onPrimary,
        ),
      ),
    );
  }
}
