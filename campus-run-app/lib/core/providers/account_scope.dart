import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';

/// 「随账号变化而失效」的 provider 约定。
///
/// 背景（真实 bug）：`friendListProvider` 这类 provider 是**全局缓存、与账号无关**的。
/// 同一设备 A 退出、B 登录后，缓存仍然保留 A 的数据，于是 B 在「社区」里看到的是
/// **A 的好友列表**（里面恰好有 B 自己），看起来就像"自己出现在自己的好友里"。
///
/// 根因不是渲染逻辑，而是**数据源没有和账号绑定**。修法有两条：
///  1. 让 provider 依赖 `authProvider`（本文件的 `watchUserId`），账号一变就自动重算；
///  2. 在登出/登录处逐个 `invalidate`（容易漏、难维护，不采用）。
///
/// 约定：**任何返回「当前登录用户私有数据」的 provider，都必须先调用 [watchUserId]**。
/// 参数已经带上 userId 的 family provider（如 `userProfileProvider(id)`）天然是分账号的，
/// 不需要调用。
extension AccountScope on Ref {
  /// 订阅登录态并返回当前用户 id。
  ///
  /// 必须在 provider 的构建体内调用（内部用 `watch`，账号切换会触发重算）。
  /// 未登录时返回 null，调用方应返回空数据而不是发请求 —— 否则登出瞬间
  /// 会带着旧令牌打一次必然 401 的请求。
  int? watchUserId() => watch(authProvider).value?.userId;
}
