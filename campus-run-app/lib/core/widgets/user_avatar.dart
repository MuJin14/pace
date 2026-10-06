import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/media_url.dart';
import '../theme/app_theme.dart';

/// 用户头像：有头像地址则加载网络图，否则用昵称首字 + 渐变底色。
///
/// ⚠️ 服务端给的是**绝对地址**（域名写在数据库里）。那个域名一旦对客户端
/// 不可达（证书、DNS、域名到期……），头像就会全部加载失败 —— 而 App 本身
/// 是连得上服务器的，表现为「能登录能聊天但头像全白」。
/// 所以这里统一用 [resolveMediaUrl] 换成当前连接地址再加载。
class UserAvatar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = nickname.isNotEmpty ? nickname.characters.first : '?';
    final resolved = resolveMediaUrl(ref, avatarUrl);
    if (resolved == null) return _fallback(initial);

    // ⚠️ 头像必须走缩略图，不能直接拉原图。
    //
    // 实测：一张 239KB 的原图缩到 96px 只有 6.6KB —— **36 倍**。
    // 而头像出现在好友列表、排行榜、聊天、搜索的**每一条列表项**里，
    // 一屏十几张原图，在服务器上行只有约 0.3MB/s 的情况下，
    // 就是用户看到的「转一会儿才显示」。
    //
    // 缩略图宽度按「显示尺寸 × 设备像素比」取，再向上取整到 32 的倍数：
    //   · 按物理像素取，避免高分屏发虚；
    //   · 取整是为了让不同页面命中同一份缓存（46 与 44 都归到 160）。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final wanted = (size * dpr).round();
    final thumbWidth = ((wanted + 31) ~/ 32) * 32;

    final thumb = resolveThumbUrl(ref, avatarUrl, width: thumbWidth);

    return ClipOval(
      child: Image.network(
        thumb ?? resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // 加载中先显示首字兜底，避免列表里出现一块空洞、再突然跳成头像
        // —— 这也是「加载一会再显示」观感的一部分。
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded || frame != null) return child;
          return _fallback(initial);
        },
        errorBuilder: (_, __, ___) => _fallback(initial),
      ),
    );
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
