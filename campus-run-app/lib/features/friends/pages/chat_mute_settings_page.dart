import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../core/widgets/user_avatar.dart';
import '../providers/chat_preference_provider.dart';
import '../providers/friend_provider.dart';

/// 消息免打扰设置。
///
/// 语义（与服务端一致，不要改错方向）：
/// - **单向**：我静音某人的消息提醒，不影响对方是否收到我的提醒。
///   （双向静音会变成「对方能单方面让你收不到消息」，容易被滥用。）
/// - **只拦通知，不拦消息**：被静音的会话照样收得到消息、照样进未读数，
///   只是不震动、不弹通知。
///
/// 开关采用乐观更新（见 [MutedFriendIdsNotifier.toggle]），点下去立刻响应，
/// 失败自动回滚并提示。
class ChatMuteSettingsPage extends ConsumerWidget {
  const ChatMuteSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendListProvider);
    final mutedAsync = ref.watch(mutedFriendIdsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('消息免打扰')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pageWide,
              AppSpacing.md,
              AppSpacing.pageWide,
              AppSpacing.sm,
            ),
            child: Text(
              '打开开关后，该好友发来的消息不再震动或弹出通知，'
              '但消息仍会正常收到并计入未读。',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: friendsAsync.when(
              loading: () => const ScrollableCenter(
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => ScrollableCenter(
                child: ErrorState(
                  message: e is ApiException ? e.message : '加载好友失败',
                  onRetry: () => ref.invalidate(friendListProvider),
                ),
              ),
              data: (friends) {
                if (friends.isEmpty) {
                  return const ScrollableCenter(
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: '还没有好友',
                      subtitle: '添加好友后，可以在这里单独设置谁的消息不打扰你',
                    ),
                  );
                }
                // 静音名单还没加载好时按「全部未静音」渲染：
                // 宁可短暂显示成关，也不要在数据未就绪时显示成开 ——
                // 后者会让用户以为自己的设置丢了。
                final muted = mutedAsync.value ?? const <int>{};

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageWide,
                  ),
                  itemCount: friends.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (context, i) {
                    final friend = friends[i];
                    final isMuted = muted.contains(friend.userId);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        nickname: friend.nickname,
                        avatarUrl: friend.avatarUrl,
                        size: AppSpacing.xxl,
                      ),
                      title: Text(
                        friend.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSize.body,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        isMuted ? '已免打扰' : '提醒开启',
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          color: AppColors.textHint,
                        ),
                      ),
                      trailing: Switch(
                        value: isMuted,
                        onChanged: (value) => _toggle(
                          context,
                          ref,
                          friend.userId,
                          value,
                        ),
                      ),
                      onTap: () => _toggle(context, ref, friend.userId, !isMuted),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    int friendId,
    bool muted,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(mutedFriendIdsProvider.notifier).toggle(friendId, muted);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '设置失败，请重试')),
      );
    }
  }
}
