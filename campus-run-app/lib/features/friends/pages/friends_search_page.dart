import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pagination_bar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/page_response.dart';
import '../../../data/models/user_brief.dart';
import '../../../data/repositories/friend_repository.dart';
import '../providers/friend_provider.dart';

/// 搜索并添加好友。
///
/// 三态：加载中 / 错误（可重试）/ 空态（含召唤语 + 可点动作）。
class FriendsSearchPage extends ConsumerStatefulWidget {
  const FriendsSearchPage({super.key});

  @override
  ConsumerState<FriendsSearchPage> createState() => _FriendsSearchPageState();
}

class _FriendsSearchPageState extends ConsumerState<FriendsSearchPage> {
  final _controller = TextEditingController();
  String _keyword = '';

  /// 当前页码（从 1 开始）。
  ///
  /// 之前没有这个字段，于是永远只拉第 1 页 —— 超过 20 人的搜索结果
  /// 被静默截断，用户以为「只有这些人」。
  int _page = 1;

  /// 正在提交申请的用户，避免重复点击。
  final Set<int> _sending = <int>{};

  /// 已成功发出申请的用户（本轮页面内）。
  final Set<int> _sent = <int>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String v) {
    final keyword = v.trim();
    if (keyword.isEmpty) {
      _toast('请输入专属 ID、昵称或手机号');
      return;
    }
    // 换关键词必须回到第 1 页：否则搜「张」在第 3 页、
    // 再搜「李」时会直接请求第 3 页，结果可能为空，看起来像搜不到。
    setState(() {
      _keyword = keyword;
      _page = 1;
    });
  }

  void _reset() {
    _controller.clear();
    setState(() {
      _keyword = '';
      _page = 1;
    });
  }

  /// 翻页。页码交给 provider 作为 family key，Riverpod 会自动缓存各页。
  void _goToPage(int page) {
    if (page < 1 || page == _page) return;
    setState(() => _page = page);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 通过对方发来的申请。
  Future<void> _accept(UserBrief user) async {
    if (_sending.contains(user.userId)) return;
    final requests = ref.read(friendRequestsProvider).value ?? const [];
    final match = requests.where((r) => r.userId == user.userId).toList();
    if (match.isEmpty) {
      _toast('没有找到来自 TA 的申请，请下拉刷新后重试');
      return;
    }
    setState(() => _sending.add(user.userId));
    try {
      await ref.read(friendRepositoryProvider).accept(match.first.requestId);
      if (!mounted) return;
      _toast('已添加「${user.nickname}」为好友');
      ref.invalidate(friendListProvider);
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(friendSearchProvider(FriendSearchQuery(_keyword, _page)));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _sending.remove(user.userId));
    }
  }

  Future<void> _add(UserBrief user) async {
    if (_sending.contains(user.userId) || _sent.contains(user.userId)) return;
    setState(() => _sending.add(user.userId));
    try {
      await ref.read(friendRepositoryProvider).sendRequest(user.userId);
      if (!mounted) return;
      setState(() => _sent.add(user.userId));
      _toast('已向「${user.nickname}」发送好友申请');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _sending.remove(user.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = FriendSearchQuery(_keyword, _page);
    final async = _keyword.isEmpty ? null : ref.watch(friendSearchProvider(query));
    return Scaffold(
      appBar: AppBar(title: const Text('添加好友')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageWide,
              AppSpacing.sm,
              AppSpacing.pageWide,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _controller,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索专属 ID / 昵称 / 手机号',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppColors.primary),
                  tooltip: '搜索',
                  onPressed: () => _search(_controller.text),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(async)),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<PageResponse<UserBrief>>? async) {
    // 未输入关键词：引导态（召唤语 + 可点动作）。
    if (async == null) {
      return ScrollableCenter(
        child: EmptyState(
          icon: Icons.search,
          title: '搜索同学',
          subtitle: '输入对方的专属 ID、昵称或手机号，添加好友一起约跑',
          actionLabel: '开始搜索',
          onAction: () => _search(_controller.text),
        ),
      );
    }

    return async.when(
      loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
      error: (err, _) => ScrollableCenter(
        child: ErrorState(
          message: err is ApiException ? err.message : '搜索失败，请稍后重试',
          onRetry: () => ref.invalidate(
              friendSearchProvider(FriendSearchQuery(_keyword, _page))),
        ),
      ),
      data: (result) {
        final list = result.list;
        if (list.isEmpty) {
          // 搜不到时只可能是关键词没匹配上（自己与好友现在都会被搜到并展示）。
          return ScrollableCenter(
            child: EmptyState(
              icon: Icons.person_search,
              title: '没有找到「$_keyword」',
              subtitle: '对方的 ID 是 8 位数字，可在「我的」页看到你自己的 ID 作为参照。\n'
                  '也可以试试对方的昵称或完整手机号。',
              actionLabel: '重新搜索',
              onAction: _reset,
            ),
          );
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
            // 用服务端返回的 total 而不是 list.length：
            // list.length 只是**本页**条数，会让人误以为总共就这么多人
            AppSectionTitle(title: '搜索结果 · 共 ${result.total} 位同学'),
            const SizedBox(height: AppSpacing.smLg),
            for (final user in list) ...[
              _UserResultCard(
                user: user,
                sending: _sending.contains(user.userId),
                sent: _sent.contains(user.userId),
                onAdd: () => _add(user),
                onAccept: () => _accept(user),
                // 整卡可点：进 TA 的主页（自己也能进，类似微信点头像看资料）
                onOpen: () => context.push('/user/${user.userId}'),
                onMessage: () => context.push(
                  '/chat/${user.userId}',
                  extra: {'name': user.nickname, 'avatarUrl': user.avatarUrl},
                ),
              ),
              const SizedBox(height: AppSpacing.gap10),
            ],
            PaginationBar(
              page: result.page,
              size: result.size,
              total: result.total,
              onPageChanged: _goToPage,
            ),
          ],
        );
      },
    );
  }
}

/// 搜索结果卡片。
///
/// 按钮由服务端给的 `relation` 决定，而不是前端猜：
/// 自己→看主页、好友→发消息、我申请过→等待中、对方申请我→通过、无关系→添加。
/// 整张卡可点，进 TA 的个人主页（类似微信点头像看资料）。
class _UserResultCard extends StatelessWidget {
  const _UserResultCard({
    required this.user,
    required this.sending,
    required this.sent,
    required this.onAdd,
    required this.onAccept,
    required this.onOpen,
    required this.onMessage,
  });

  final UserBrief user;
  final bool sending;
  final bool sent;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onOpen;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gap14),
          child: Row(
            children: [
              UserAvatar(nickname: user.nickname, avatarUrl: user.avatarUrl, size: 46),
              const SizedBox(width: AppSpacing.smLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppFontSize.title,
                              fontWeight: AppFontWeight.medium,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (user.isSelf) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const _RelationTag(text: '我'),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      Formatters.uniqueId(user.uniqueId),
                      style: const TextStyle(
                        fontSize: AppFontSize.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _trailing(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    // 自己：只能看主页，不能加自己
    if (user.isSelf) {
      return const _GhostHint(text: '我的主页');
    }
    // 已是好友：直接聊天
    if (user.isFriend) {
      return _SmallButton(
        icon: Icons.chat_bubble_outline,
        label: '发消息',
        onPressed: onMessage,
        filled: false,
      );
    }
    // 对方已申请我：一键通过
    if (user.isPendingIncoming) {
      return _SmallButton(
        icon: Icons.how_to_reg_outlined,
        label: '通过',
        onPressed: sending ? null : onAccept,
        loading: sending,
      );
    }
    // 我已申请：等待中（本轮刚提交的也用 chip 覆盖，避免重复点）
    if (user.isPendingOutgoing || sent) {
      return const _GhostHint(text: '等待通过');
    }
    return _SmallButton(
      icon: Icons.person_add_alt,
      label: '添加',
      onPressed: sending ? null : onAdd,
      loading: sending,
    );
  }
}

class _RelationTag extends StatelessWidget {
  const _RelationTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Text(
        '我',
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: AppFontWeight.bold,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _GhostHint extends StatelessWidget {
  const _GhostHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.gap10,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppFontSize.body,
          fontWeight: AppFontWeight.bold,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: filled ? AppColors.primary : AppColors.primaryLight,
      foregroundColor: filled ? AppColors.onPrimary : AppColors.primaryDark,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.gap10,
      ),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final child = loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Text(label),
            ],
          );
    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}
