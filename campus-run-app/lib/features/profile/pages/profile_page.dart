import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/platform/external_link.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';

/// 个人中心：用户信息 + 功能入口 + 退出登录。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(
          message: err is ApiException ? err.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(authProvider),
        ),
        data: (user) {
          if (user == null) {
            return EmptyState(
              icon: Icons.person_outline,
              title: '还没有登录',
              subtitle: '登录后查看你的运动档案与勋章',
              actionLabel: '去登录',
              onAction: () => context.go('/login'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            children: [
              // 整卡可点进「我的主页」：和看别人是同一个页面，
              // 这样自己的 ID 在主页里更醒目，方便念给别人加好友。
              GestureDetector(
                onTap: () => context.push('/user/${user.userId}'),
                child: _UserCard(user: user),
              ),
              const SizedBox(height: AppSpacing.lg),
              _MenuCard(
                items: [
                  _MenuItem(
                    icon: Icons.badge_outlined,
                    label: '我的主页',
                    onTap: () => context.push('/user/${user.userId}'),
                  ),
                  _MenuItem(
                    icon: Icons.directions_run_outlined,
                    label: '运动记录',
                    onTap: () => context.push('/activity'),
                  ),
                  _MenuItem(
                    icon: Icons.flag_outlined,
                    label: '运动目标',
                    onTap: () => context.push('/goals'),
                  ),
                  _MenuItem(
                    icon: Icons.emoji_events_outlined,
                    label: '我的勋章',
                    onTap: () => context.push('/badges'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // 管理后台入口：**只有管理员看得到**。
              // 藏起来只是 UI 便利 —— 服务端每个接口都有 @PreAuthorize，
              // 普通用户即使猜到路径也调不动。
              if (user.isAdmin) ...[
                _MenuCard(
                  items: [
                    _MenuItem(
                      icon: Icons.admin_panel_settings_outlined,
                      label: '管理后台',
                      color: AppColors.gold,
                      onTap: () => context.push('/admin'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _MenuCard(
                items: [
                  _MenuItem(
                    icon: Icons.lock_outline,
                    label: '修改密码',
                    onTap: () => context.push('/profile/password'),
                  ),
                  _MenuItem(
                    icon: Icons.help_outline,
                    label: '忘记密码怎么办',
                    onTap: () => context.push('/forgot-password'),
                  ),
                  _MenuItem(
                    icon: Icons.notifications_active_outlined,
                    label: '后台消息提醒',
                    onTap: () => context.push('/profile/background'),
                  ),
                  _MenuItem(
                    icon: Icons.description_outlined,
                    label: '用户协议与隐私政策',
                    onTap: () => context.push('/privacy'),
                  ),
                  _MenuItem(
                    // 项目已开源，源码与每个版本的安装包都在 GitHub 上。
                    // 放在「我的」里常驻，用户不必等到有更新时才能找到它。
                    icon: Icons.code,
                    label: '开源仓库（GitHub）',
                    onTap: () => _openGitHub(context),
                  ),
                  _MenuItem(
                    icon: Icons.logout,
                    label: '退出登录',
                    color: AppColors.danger,
                    onTap: () => _confirmLogout(context, ref),
                  ),
                  _MenuItem(
                    icon: Icons.delete_forever_outlined,
                    label: '注销账号',
                    color: AppColors.danger,
                    onTap: () => _confirmDeleteAccount(context, ref),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 打开项目的 GitHub 仓库。
  ///
  /// 失败时必须给提示：如果只是「点了没反应」，用户会当成 App 坏了。
  /// 这里最常见的失败原因是设备上没有浏览器（少见）或原生通道异常。
  Future<void> _openGitHub(BuildContext context) async {
    final ok = await ExternalLink.open(ProjectLinks.repository);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('没能打开浏览器，仓库地址：${ProjectLinks.repository}')),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  /// 注销账号：不可恢复，故用「说明后果 + 确认弹窗」双重确认。
  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    // 在任何 await 之前取好依赖 BuildContext 的对象，
    // 避免跨异步边界使用 context（use_build_context_synchronously）。
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(authRepositoryProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注销账号'),
        content: const Text(
          '注销后将永久删除你的账号与全部数据，包括：\n'
          '· 所有运动记录与轨迹\n'
          '· 好友关系与聊天记录\n'
          '· 排行榜数据、运动目标、已获勋章\n\n'
          '删除后无法恢复，手机号可重新注册。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('确认注销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteAccount();
      // 本地令牌已无意义（服务端账号已删除），清空并回到未登录态。
      await ref.read(authProvider.notifier).logout();
      messenger.showSnackBar(const SnackBar(content: Text('账号已注销')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '注销失败，请稍后重试')),
      );
    }
  }
}

/// 个人信息卡片：设计系统渐变卡（24 圆角 + 品牌渐变）。
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final nickname = user.nickname;
    final uniqueId = user.uniqueId;
    final phone = user.phone;
    return AppDashboardCard(
      gradientColors: AppColors.primaryGradient,
      radius: AppRadius.lg,
      child: Row(
        children: [
          UserAvatar(nickname: nickname, avatarUrl: user.avatarUrl, size: 64),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.headline,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _tag(Formatters.uniqueId(uniqueId)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  phone,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppFontSize.caption,
          color: AppColors.onPrimary,
          fontWeight: AppFontWeight.bold,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});

  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              onTap: items[i].onTap,
              leading: Icon(
                items[i].icon,
                color: items[i].color ?? AppColors.textPrimary,
              ),
              title: Text(
                items[i].label,
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  color: items[i].color ?? AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}
