import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/user.dart';
import '../../auth/providers/auth_provider.dart';

/// 个人中心：用户信息 + 功能入口 + 退出登录。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _UserCard(user: user),
          const SizedBox(height: 20),
          _MenuCard(
            items: [
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
          const SizedBox(height: 20),
          _MenuCard(
            items: [
              _MenuItem(
                icon: Icons.logout,
                label: '退出登录',
                color: AppColors.danger,
                onTap: () => _confirmLogout(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final nickname = user?.nickname ?? '';
    final uniqueId = user?.uniqueId ?? '';
    final phone = user?.phone ?? '';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          UserAvatar(nickname: nickname, avatarUrl: user?.avatarUrl, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 6),
                _tag(uniqueId),
                const SizedBox(height: 6),
                Text(phone, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});

  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              onTap: items[i].onTap,
              leading: Icon(items[i].icon, color: items[i].color ?? AppColors.textPrimary),
              title: Text(
                items[i].label,
                style: TextStyle(fontSize: 15, color: items[i].color ?? AppColors.textPrimary),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}
