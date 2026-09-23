import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 用户头像：有头像地址则加载网络图，否则用昵称首字 + 渐变底色。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.nickname = '',
    this.avatarUrl,
    this.size = 44,
  });

  final String nickname;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = nickname.isNotEmpty ? nickname.characters.first : '?';
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(initial),
        ),
      );
    }
    return _fallback(initial);
  }

  Widget _fallback(String initial) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
