import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/friend_item.dart';
import '../../../data/models/friend_request.dart';
import '../../../data/repositories/friend_repository.dart';
import '../providers/friend_provider.dart';

/// 好友页：待处理申请 + 好友列表。
class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendListProvider);
    final requestsAsync = ref.watch(friendRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _RequestsSection(async: requestsAsync),
            const SizedBox(height: 16),
            Text(
              '我的好友',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            _FriendsSection(async: friendsAsync),
          ],
        ),
      ),
    );
  }
}

class _RequestsSection extends ConsumerWidget {
  const _RequestsSection({required this.async});

  final AsyncValue<List<FriendRequest>> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = async.value ?? const <FriendRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '好友申请',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        ...requests.map((r) => _RequestCard(
              request: r,
              onAccept: () => _act(context, ref, () => ref.read(friendRepositoryProvider).accept(r.requestId)),
              onReject: () => _act(context, ref, () => ref.read(friendRepositoryProvider).reject(r.requestId)),
            )),
      ],
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(friendListProvider);
      ref.invalidate(friendRequestsProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onAccept, required this.onReject});

  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          UserAvatar(nickname: request.nickname, avatarUrl: request.avatarUrl, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.nickname, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(request.uniqueId, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onReject,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.textSecondary.withValues(alpha: 0.1),
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('拒绝'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAccept,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => _ErrorView(
        message: err is ApiException ? err.message : '加载失败',
        onRetry: () => ref.invalidate(friendListProvider),
      ),
      data: (friends) {
        if (friends.isEmpty) {
          return const EmptyState(
            icon: Icons.people_outline,
            title: '还没有好友',
            subtitle: '点击右上角添加好友，一起约跑吧',
          );
        }
        return Column(
          children: friends.map((f) => _FriendItem(
                friend: f,
                onTap: () => context.push('/chat/${f.userId}', extra: f.nickname),
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
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _FriendItem extends StatelessWidget {
  const _FriendItem({required this.friend, required this.onTap, required this.onDelete});

  final FriendItem friend;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,
        leading: UserAvatar(nickname: friend.nickname, avatarUrl: friend.avatarUrl, size: 46),
        title: Text(friend.nickname, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        subtitle: Text(friend.uniqueId, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textHint),
          onSelected: (v) {
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'delete', child: Text('删除好友')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
