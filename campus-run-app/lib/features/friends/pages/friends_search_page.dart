import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/page_response.dart';
import '../../../data/models/user_brief.dart';
import '../../../data/repositories/friend_repository.dart';
import '../providers/friend_provider.dart';

/// 搜索并添加好友。
class FriendsSearchPage extends ConsumerStatefulWidget {
  const FriendsSearchPage({super.key});

  @override
  ConsumerState<FriendsSearchPage> createState() => _FriendsSearchPageState();
}

class _FriendsSearchPageState extends ConsumerState<FriendsSearchPage> {
  final _controller = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String v) {
    setState(() => _keyword = v.trim());
  }

  Future<void> _add(UserBrief user) async {
    try {
      await ref.read(friendRepositoryProvider).sendRequest(user.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已向「${user.nickname}」发送好友申请')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _keyword.isEmpty
        ? null
        : ref.watch(friendSearchProvider(_keyword)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('添加好友')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              controller: _controller,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索专属 ID / 昵称 / 手机号',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppColors.primary),
                  onPressed: () => _search(_controller.text),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(result)),
        ],
      ),
    );
  }

  Widget _buildBody(PageResponse<UserBrief>? result) {
    if (_keyword.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: '搜索同学',
        subtitle: '输入对方的专属 ID、昵称或手机号',
      );
    }
    if (result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = result.list;
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search,
        title: '没有找到相关用户',
        subtitle: '试试其他关键词',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final user = list[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              UserAvatar(nickname: user.nickname, avatarUrl: user.avatarUrl, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.nickname, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(user.uniqueId, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _add(user),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('添加'),
              ),
            ],
          ),
        );
      },
    );
  }
}
