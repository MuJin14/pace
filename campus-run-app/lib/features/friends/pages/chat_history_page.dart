import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../data/models/chat_message.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/message_provider.dart';

/// 聊天记录（微信式：聊天页右上角「三个点 → 查看聊天记录」）。
///
/// 只读展示，不提供再编辑；按时间倒序（最新在上），符合「翻聊天记录」的习惯。
class ChatHistoryPage extends ConsumerWidget {
  const ChatHistoryPage({
    super.key,
    required this.friendId,
    required this.friendName,
  });

  final int friendId;
  final String friendName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(messageHistoryProvider(friendId));
    // 判断「这条是我发的吗」需要当前用户 id；拿不到时按「对方」显示，
    // 只影响标签文案，不影响消息内容。
    final myId = ref.watch(authProvider).value?.userId ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('$friendName · 聊天记录')),
      body: async.when(
        loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
        error: (err, _) => ScrollableCenter(
          child: ErrorState(
            message: '聊天记录加载失败，请稍后重试',
            onRetry: () => ref.invalidate(messageHistoryProvider(friendId)),
          ),
        ),
        data: (page) {
          if (page.list.isEmpty) {
            return const ScrollableCenter(
              child: EmptyState(
                icon: Icons.forum_outlined,
                title: '还没有聊天记录',
                subtitle: '回到聊天页打个招呼，这里就会出现你们的往来消息',
              ),
            );
          }
          // 后端按 messageId 倒序返回（最新在前），正是「聊天记录」要的顺序
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageWide,
              AppSpacing.md,
              AppSpacing.pageWide,
              AppSpacing.xl,
            ),
            itemCount: page.list.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.dividerLight),
            itemBuilder: (context, i) =>
                _HistoryRow(message: page.list[i], myId: myId),
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.message, required this.myId});

  final ChatMessage message;
  final int myId;

  @override
  Widget build(BuildContext context) {
    final mine = message.senderId == myId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              mine ? '我' : '对方',
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: AppFontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: AppFontSize.body,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  Formatters.dateTime(
                    DateTime.fromMillisecondsSinceEpoch(message.timestamp)
                        .toIso8601String(),
                  ),
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
