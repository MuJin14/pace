import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/activity_summary.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/friend_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../../friends/providers/chat_preference_provider.dart';
import '../../friends/providers/friend_provider.dart';

/// 用户主页：看自己 / 看别人，类似微信的个人资料页。
///
/// 关键设计：**按钮由服务端返回的 relation 决定**，而不是前端猜。
/// 这样「已是好友」必定显示「发消息」、「对方申请我」必定显示「通过验证」，
/// 不会出现「看起来能聊但发送被拒」这类不一致。
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 执行一次「改变关系」的操作，成功后刷新主页让按钮状态跟着更新。
  Future<void> _act(Future<void> Function() action, String successMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(successMessage);
      ref.invalidate(userProfileProvider(widget.userId));
      // 好友列表/申请列表也要刷新，否则返回上一页看到的还是旧状态
      ref.invalidate(friendListProvider);
      ref.invalidate(friendRequestsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userProfileProvider(widget.userId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('个人资料'),
        actions: [
          // 右上角「三个点」：看别人时提供「消息免打扰」——
          // 与微信一致（在对方资料页设置，不必进聊天页再翻菜单）。
          // 只有「别人」才显示：对自己的资料页设置「免打扰自己」没有意义。
          async.maybeWhen(
            data: (profile) => profile.isSelf
                ? const SizedBox.shrink()
                : _ProfileMenu(profile: profile),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
        error: (err, _) => ScrollableCenter(
          child: ErrorState(
            message: err is ApiException ? err.message : '资料加载失败，请稍后重试',
            onRetry: () => ref.invalidate(userProfileProvider(widget.userId)),
          ),
        ),
        data: (profile) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageWide,
            AppSpacing.md,
            AppSpacing.pageWide,
            AppSpacing.xl,
          ),
          children: [
            _HeaderCard(profile: profile),
            const SizedBox(height: AppSpacing.lg),
            _StatsCard(profile: profile),
            const SizedBox(height: AppSpacing.lg),
            _ActionArea(
              profile: profile,
              busy: _busy,
              onMessage: () => context.push(
                '/chat/${profile.userId}',
                extra: {'name': profile.nickname, 'avatarUrl': profile.avatarUrl},
              ),
              onAdd: () => _act(
                () => ref.read(friendRepositoryProvider).sendRequest(profile.userId),
                '已向「${profile.nickname}」发送好友申请',
              ),
              onAccept: () => _acceptIncoming(profile),
              onReject: () => _rejectIncoming(profile),
              onEdit: () => _openEdit(),
              onDelete: () => _confirmDeleteFriend(profile),
            ),
            // 好友才拉取 TA 的运动记录与勋章：接口对非好友返回 403，
            // 不预先判断会导致每个陌生人都白打两次请求。
            if (profile.isFriend || profile.isSelf) ...[
              const SizedBox(height: AppSpacing.lg),
              _BadgesSection(userId: profile.userId),
              const SizedBox(height: AppSpacing.lg),
              _ActivitiesSection(userId: profile.userId),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openEdit() async {
    final changed = await context.push<bool>('/profile/edit');
    if (changed == true && mounted) {
      // 昵称/头像改了，主页与登录态都要刷新
      ref.invalidate(userProfileProvider(widget.userId));
      _toast('资料已更新');
    }
  }

  /// 对方已申请我：从我的申请列表里找到对应 requestId 再通过。
  Future<void> _acceptIncoming(UserProfile profile) async {
    final requests = ref.read(friendRequestsProvider).value ?? const [];
    final match = requests.where((r) => r.userId == profile.userId).toList();
    if (match.isEmpty) {
      _toast('没有找到来自 TA 的申请，请刷新后重试');
      return;
    }
    await _act(
      () => ref.read(friendRepositoryProvider).accept(match.first.requestId),
      '已添加「${profile.nickname}」为好友',
    );
  }

  /// 删除好友：只删单向关系（后端会处理双向），需二次确认。
  Future<void> _confirmDeleteFriend(UserProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除「${profile.nickname}」吗？删除后需要重新申请才能成为好友。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(
      () => ref.read(friendRepositoryProvider).delete(profile.userId),
      '已删除好友「${profile.nickname}」',
    );
  }

  /// 拒绝对方申请：按项目约定 = 删除 PENDING 记录（不保留 REJECTED 状态）。
  Future<void> _rejectIncoming(UserProfile profile) async {
    final requests = ref.read(friendRequestsProvider).value ?? const [];
    final match = requests.where((r) => r.userId == profile.userId).toList();
    if (match.isEmpty) {
      _toast('没有找到来自 TA 的申请，请刷新后重试');
      return;
    }
    await _act(
      () => ref.read(friendRepositoryProvider).reject(match.first.requestId),
      '已忽略「${profile.nickname}」的申请',
    );
  }
}

// ── 头部：头像 + 昵称 + ID + 关系 ────────────────────────────────
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return AppDashboardCard(
      gradientColors: AppColors.primaryGradient,
      radius: AppRadius.lg,
      child: Column(
        children: [
          UserAvatar(
            nickname: profile.nickname,
            avatarUrl: profile.avatarUrl,
            size: 84,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            profile.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppFontSize.headline,
              fontWeight: AppFontWeight.bold,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 性别 / 年龄：**只在对方公开时才渲染**。
          //
          // 后端在未公开时直接不返回这两个字段（值为 null），
          // 所以这里只判断「有没有值」，不需要再查可见性开关 ——
          // 「不公开」在客户端根本无法被反推出来。
          if (profile.hasPublicProfileInfo) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (profile.genderLabel != null)
                  _ProfileTag(label: profile.genderLabel!),
                if (profile.genderLabel != null && profile.age != null)
                  const SizedBox(width: AppSpacing.sm),
                if (profile.age != null) _ProfileTag(label: '${profile.age} 岁'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smLg,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              Formatters.uniqueId(profile.uniqueId),
              style: const TextStyle(
                fontSize: AppFontSize.body,
                fontWeight: AppFontWeight.bold,
                color: AppColors.onPrimary,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link, size: 14, color: AppColors.onPrimary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                profile.relationLabel,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: AppColors.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主页顶部的性别 / 年龄小标签（半透明胶囊，叠在渐变背景上）。
class _ProfileTag extends StatelessWidget {
  const _ProfileTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gap10,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: AppFontSize.hint,
          fontWeight: AppFontWeight.medium,
          color: AppColors.onPrimary,
        ),
      ),
    );
  }
}

// ── 运动汇总 ────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final joined = profile.createdAt == null ? null : Formatters.monthDay(profile.createdAt);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '运动数据',
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  value: Formatters.distance(profile.totalDistanceMeters),
                  label: '累计距离',
                ),
              ),
              const _CellDivider(),
              Expanded(
                child: _StatCell(
                  value: '${profile.totalActivityCount}',
                  label: '运动次数',
                ),
              ),
              const _CellDivider(),
              Expanded(
                child: _StatCell(
                  value: '${profile.streakDays}',
                  label: '连续天数',
                ),
              ),
            ],
          ),
          if (joined != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              '加入于 $joined',
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: AppFontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: const TextStyle(
            fontSize: AppFontSize.caption,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CellDivider extends StatelessWidget {
  const _CellDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: AppColors.dividerLight);
  }
}

// ── 操作区：按关系渲染按钮 ──────────────────────────────────────
class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.profile,
    required this.busy,
    required this.onMessage,
    required this.onAdd,
    required this.onAccept,
    required this.onReject,
    required this.onEdit,
    required this.onDelete,
  });

  final UserProfile profile;
  final bool busy;
  final VoidCallback onMessage;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (profile.isSelf) {
      // 自己：给「编辑资料」入口，而不是一片空白
      return _PrimaryAction(
        icon: Icons.edit_outlined,
        label: '编辑资料',
        busy: false,
        onTap: onEdit,
      );
    }

    if (profile.isFriend) {
      return Row(
        children: [
          Expanded(
            child: _PrimaryAction(
              icon: Icons.chat_bubble_outline,
              label: '发消息',
              busy: false,
              onTap: onMessage,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SecondaryAction(
              icon: Icons.person_remove_outlined,
              label: '删除好友',
              onTap: onDelete,
            ),
          ),
        ],
      );
    }

    if (profile.isPendingOutgoing) {
      return _DisabledHint(
        icon: Icons.hourglass_top,
        text: '已发送好友申请，等待对方通过。通过后即可聊天。',
      );
    }

    if (profile.isPendingIncoming) {
      // 对方申请我：通过 + 忽略 两个动作都给，避免只能通过不能拒绝
      return Row(
        children: [
          Expanded(
            child: _PrimaryAction(
              icon: Icons.how_to_reg_outlined,
              label: '通过好友申请',
              busy: busy,
              onTap: onAccept,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SecondaryAction(
              icon: Icons.close,
              label: '忽略',
              onTap: busy ? null : onReject,
            ),
          ),
        ],
      );
    }

    return _PrimaryAction(
      icon: Icons.person_add_alt,
      label: '添加好友',
      busy: busy,
      onTap: onAdd,
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _DisabledHint extends StatelessWidget {
  const _DisabledHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: AppFontSize.body,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
    );
  }
}

/// TA 的勋章墙（仅好友可见，接口对非好友返回 403）。
class _BadgesSection extends ConsumerWidget {
  const _BadgesSection({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userBadgesProvider(userId));
    return async.when(
      loading: () => const _SectionSkeleton(title: 'TA 的勋章'),
      // 非好友 / 网络异常：整块静默隐藏，不打断主页浏览
      error: (_, __) => const SizedBox.shrink(),
      data: (badges) {
        if (badges.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle(title: 'TA 的勋章'),
            const SizedBox(height: AppSpacing.smLg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final b in badges)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.smLg,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.iconBgWarm,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events,
                              size: 16, color: AppColors.medal),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            b.name,
                            style: const TextStyle(
                              fontSize: AppFontSize.body,
                              fontWeight: AppFontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// TA 的近期运动（仅好友可见，接口对非好友返回 403）。
class _ActivitiesSection extends ConsumerWidget {
  const _ActivitiesSection({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userActivitiesProvider(userId));
    return async.when(
      loading: () => const _SectionSkeleton(title: 'TA 的近期运动'),
      error: (_, __) => const SizedBox.shrink(),
      data: (page) {
        final list = page.list.take(5).toList();
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle(title: 'TA 的近期运动'),
            const SizedBox(height: AppSpacing.smLg),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: AppColors.dividerLight),
                    _ActivityRow(item: list[i]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final ActivitySummary item;

  @override
  Widget build(BuildContext context) {
    final isRun = item.type == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smLg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isRun ? AppColors.iconBgPeach : AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              isRun ? Icons.directions_run : Icons.directions_bike,
              size: 20,
              color: isRun ? AppColors.accentHot : AppColors.ride,
            ),
          ),
          const SizedBox(width: AppSpacing.smLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRun ? '跑步' : '骑行',
                  style: const TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  Formatters.relativeTime(item.startTime),
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Formatters.distance(item.distanceMeters),
            style: const TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(title: title),
          const SizedBox(height: AppSpacing.smLg),
          const AppCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 右上角「三个点」：消息免打扰 ────────────────────────────────

/// 他人资料页右上角的菜单。
///
/// 为什么放在资料页而不是只在聊天页：用户往往还没开始聊天就决定
/// 「这个人我不想被打扰」（例如群里加来的陌生人）。微信也是这个位置。
///
/// 语义与服务端一致：**只拦推送通知，不拦消息**。被免打扰的人发来的消息
/// 照常收到、照常计入未读，只是不震动、不弹通知。
class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只订阅「这个好友」的静音状态，避免别人开关免打扰时这里也跟着重建。
    final muted = ref.watch(
      mutedFriendIdsProvider.select((s) => s.value?.contains(profile.userId) ?? false),
    );

    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        switch (value) {
          case 'toggle_mute':
            try {
              await ref
                  .read(mutedFriendIdsProvider.notifier)
                  .toggle(profile.userId, !muted);
              messenger.showSnackBar(SnackBar(
                content: Text(!muted
                    ? '已对「${profile.nickname}」开启消息免打扰'
                    : '已恢复「${profile.nickname}」的消息提醒'),
              ));
            } catch (e) {
              messenger.showSnackBar(SnackBar(
                content: Text(e is ApiException ? e.message : '设置失败，请重试'),
              ));
            }
          case 'chat':
            context.push(
              '/chat/${profile.userId}',
              extra: {'name': profile.nickname, 'avatarUrl': profile.avatarUrl},
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'toggle_mute',
          child: Row(
            children: [
              Icon(
                muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                size: AppSpacing.block,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(muted ? '取消消息免打扰' : '消息免打扰'),
            ],
          ),
        ),
        if (profile.isFriend)
          PopupMenuItem(
            value: 'chat',
            child: Row(
              children: const [
                Icon(Icons.chat_bubble_outline,
                    size: AppSpacing.block, color: AppColors.textSecondary),
                SizedBox(width: AppSpacing.sm),
                Text('发消息'),
              ],
            ),
          ),
      ],
    );
  }
}