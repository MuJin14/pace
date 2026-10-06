import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../activity/pages/start_sheet.dart';
import '../../notifications/providers/notifications_provider.dart';

/// 底部导航外壳。承载 4 个一级 Tab + 中央凸起运动按钮。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  // 更新检查**不在这里**。这个 Widget 挂在登录后的 StatefulShellRoute 上，
  // 把检查放这里意味着「没登录就永远不检查新版本」（用户反馈过这个现象）。
  // 现在由根组件 lib/app.dart 负责，与是否登录、走到哪一页都无关。

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    // 红点统一来自聚合通知 provider（好友申请 ∪ 未读消息 ∪ 勋章 ∪ 目标达成）
    final hasNotifications = ref.watch(hasNotificationsProvider);

    return Scaffold(
      body: navigationShell,
      floatingActionButton: _StartFab(onPressed: () => _openStartSheet(context)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 72,
        color: AppColors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        padding: EdgeInsets.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tab(context, navigationShell, 0, Icons.home_outlined, Icons.home, '首页'),
            _tab(context, navigationShell, 1, Icons.emoji_events_outlined,
                Icons.emoji_events, '排行'),
            _tab(
              context,
              navigationShell,
              2,
              Icons.groups_outlined,
              Icons.groups,
              '社区',
              showBadge: hasNotifications,
              onTap: () {
                // ⚠️ 这里**不能**清空未读。
                //
                // 原先这里调了 `clearMessage()`（清空全部未读），大概是想着
                // 「进社区就算看过了」。但红点的语义是「这条消息你还没读」，
                // 而切到社区只是看到好友列表，并没有读任何一条消息 ——
                // 用户切走再回来就发现红点全没了，明明还没点进去看过。
                //
                // 正确的清除时机只有两个：
                //   · 真正进入某个会话（chat_page 里 clearFriend）；
                //   · 用户在通知页点「全部已读」（notifications_page）。
                navigationShell.goBranch(
                  2,
                  initialLocation: navigationShell.currentIndex == 2,
                );
              },
            ),
            _tab(context, navigationShell, 3, Icons.person_outlined, Icons.person, '我的'),
          ],
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    StatefulNavigationShell navigationShell,
    int index,
    IconData outlined,
    IconData filled,
    String label, {
    bool showBadge = false,
    VoidCallback? onTap,
  }) {
    final selected = navigationShell.currentIndex == index;
    return Expanded(
      child: _TabItem(
        icon: selected ? filled : outlined,
        label: label,
        selected: selected,
        showBadge: showBadge,
        onTap: onTap ??
            () => navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                ),
      ),
    );
  }

  Future<void> _openStartSheet(BuildContext context) async {
    final type = await showStartSheet(context);
    if (type != null && context.mounted) {
      context.push('/start-run', extra: type);
    }
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showBadge = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      splashColor: AppColors.primary.withValues(alpha: 0.15),
      highlightColor: AppColors.primary.withValues(alpha: 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(icon, color: color, size: 24)),
                if (showBadge)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              color: color,
              fontWeight: selected ? AppFontWeight.bold : AppFontWeight.regular,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartFab extends StatelessWidget {
  const _StartFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: AppShadows.fab,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: const Icon(Icons.directions_run, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}
