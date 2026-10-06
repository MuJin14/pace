import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/providers/notifications_provider.dart';

/// 顶栏尺寸（设计稿 §1：顶栏 56、头像 40、右侧图标按钮 36×36）。
const double _barHeight = 56;
const double _iconButtonSize = 36;
const double _iconSize = 18;
const double _badgeDotSize = 8;

/// 首页顶栏：头像 40 + 问候/日期 + 通知（未读红点）/ 设置。
///
/// 整条高 56，水平内边距由页面提供（[AppSpacing.pageWide] = 20）。
/// 通知按钮跳 `/notifications`，设置按钮跳 `/profile`。
class HomeTopBar extends ConsumerWidget {
  const HomeTopBar({super.key, required this.dateText});

  /// 日期行文案，由页面统一格式化（如「周一 · 9月23日 · 晴 18°」）。
  final String dateText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    // 红点接通知聚合 provider（好友申请 / 未读消息 / 勋章 / 目标达成）。
    final hasUnread = ref.watch(hasNotificationsProvider);
    final nickname = user?.nickname ?? '';

    return SizedBox(
      height: _barHeight,
      child: Row(
        children: [
          UserAvatar(
            nickname: nickname,
            avatarUrl: user?.avatarUrl,
            size: AppSpacing.xxl,
          ),
          const SizedBox(width: AppSpacing.smLg),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '早上好，$nickname',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.greeting,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.hint,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _TopBarIconButton(
            icon: Icons.notifications_none,
            badge: hasUnread,
            onTap: () => context.push('/notifications'),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 「三个点」菜单：把设置类入口收在一处。
          // 原先这里是直接的设置图标，加「消息免打扰」后入口变多，
          // 平铺成三个图标会挤占顶栏宽度（昵称会被截断）。
          PopupMenuButton<_TopBarAction>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
            onSelected: (action) {
              switch (action) {
                case _TopBarAction.mute:
                  context.push('/chat-mute');
                case _TopBarAction.editProfile:
                  context.push('/profile/edit');
                case _TopBarAction.changePassword:
                  context.push('/profile/password');
                case _TopBarAction.myProfile:
                  context.push('/profile');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TopBarAction.mute,
                child: _MenuRow(icon: Icons.notifications_off_outlined, label: '消息免打扰'),
              ),
              PopupMenuItem(
                value: _TopBarAction.editProfile,
                child: _MenuRow(icon: Icons.edit_outlined, label: '编辑资料'),
              ),
              PopupMenuItem(
                value: _TopBarAction.changePassword,
                child: _MenuRow(icon: Icons.lock_outline, label: '修改密码'),
              ),
              PopupMenuItem(
                value: _TopBarAction.myProfile,
                child: _MenuRow(icon: Icons.person_outline, label: '我的'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶栏「三个点」里的动作。
enum _TopBarAction { mute, editProfile, changePassword, myProfile }

/// 菜单项：图标 + 文案，间距统一。
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppSpacing.block, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: const TextStyle(fontSize: AppFontSize.body)),
      ],
    );
  }
}

/// 36×36 白底描边图标按钮，右上角可带未读红点。
class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({required this.icon, this.badge = false, this.onTap});

  final IconData icon;
  final bool badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _iconButtonSize,
        height: _iconButtonSize,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(width: 1, color: AppColors.borderLight),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(icon, size: _iconSize, color: AppColors.textPrimary),
            ),
            if (badge)
              Positioned(
                right: AppSpacing.gap6,
                top: AppSpacing.gap6,
                child: Container(
                  width: _badgeDotSize,
                  height: _badgeDotSize,
                  decoration: const BoxDecoration(
                    color: AppColors.accentHot,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
