import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../../data/models/activity_summary.dart';
import '../../../data/models/auth_result.dart';
import '../../../data/models/page_response.dart';
import '../../../data/models/user.dart';
import '../../../data/models/user_badge.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/friend_repository.dart';

/// 任意用户的公开主页（按 userId）。
///
/// autoDispose：离开主页即释放，避免浏览多人后缓存无限增长。
final userProfileProvider =
    FutureProvider.autoDispose.family<UserProfile, int>((ref, userId) {
  return ref.read(authRepositoryProvider).profile(userId);
});

/// 某人的运动记录（仅好友可见，接口会对其余人返回 403）。
final userActivitiesProvider = FutureProvider.autoDispose
    .family<PageResponse<ActivitySummary>, int>((ref, userId) {
  return ref.read(friendRepositoryProvider).userActivities(userId);
});

/// 某人的勋章墙（仅好友可见）。
final userBadgesProvider =
    FutureProvider.autoDispose.family<List<UserBadge>, int>((ref, userId) {
  return ref.read(friendRepositoryProvider).userBadges(userId);
});

/// 登录态：`AsyncValue<User?>`。
/// null = 未登录；非 null = 已登录。路由据此重定向。
///
/// **注意**：只有「服务端明确拒绝令牌（401）」才等于未登录。网络不可用时
/// `build()` 会抛错进入 error 态（而不是返回 null），否则弱网启动会把已登录用户
/// 误判为未登录、直接踢到登录页，用户会以为「账号被登出了」。
final authProvider = AsyncNotifierProvider<AuthNotifier, User?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final token = await ref.read(tokenStorageProvider).read();
    if (token == null || token.isEmpty) return null;
    try {
      return await ref.read(authRepositoryProvider).me();
    } on UnauthorizedException {
      // 令牌确实失效：清空两类令牌，回到未登录。
      await ref.read(tokenStorageProvider).clearAll();
      return null;
    }
    // 其它异常（网络超时、DNS 失败、5xx）**不再吞掉**：
    // 让它冒泡成 AsyncError，由 SplashScreen 展示「网络异常 + 重试」，
    // 令牌保持不动，用户重试即可恢复登录态。
  }

  /// 网络错误后的重试入口（SplashScreen 的「重试」按钮调用）。
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  Future<void> login(String phone, String password) =>
      _authenticate(() => ref.read(authRepositoryProvider).login(phone, password));

  Future<void> register(String phone, String password, String nickname) =>
      _authenticate(() => ref.read(authRepositoryProvider).register(phone, password, nickname));

  Future<void> logout() async {
    // 清空两类令牌：只清 access 会导致残留的 refresh token 仍可换新令牌。
    await ref.read(tokenStorageProvider).clearAll();
    state = const AsyncData(null);
  }

  /// 更新自己的资料并同步登录态里的用户信息。
  ///
  /// 关键点：更新后必须刷新 `authProvider`，否则「我的」页、首页顶栏
  /// 仍在用旧昵称/旧头像（它们读的是登录态里的缓存用户）。
  ///
  /// 可空参数 = 不修改该字段（PATCH 语义）。可见性用 `bool?`：
  /// 后端无法区分「没传」与「传 false」，所以「不改可见性」必须靠 null 表达。
  Future<User> updateProfile({
    String? nickname,
    String? avatarUrl,
    int? gender,
    int? age,
    bool? genderPublic,
    bool? agePublic,
  }) async {
    final updated = await ref.read(authRepositoryProvider).updateProfile(
          nickname: nickname,
          avatarUrl: avatarUrl,
          gender: gender,
          age: age,
          genderPublic: genderPublic,
          agePublic: agePublic,
        );
    state = AsyncData(updated);
    return updated;
  }

  /// 修改密码。
  ///
  /// ⚠️ 服务端改密后会**吊销此前签发的所有 refresh token**，也就是当前设备上的
  /// 令牌立刻失效。所以这里成功后直接清空本地令牌并把登录态置空 ——
  /// 不清的话 App 会拿已失效的令牌反复请求、反复 401，表现为「卡住转圈」。
  /// 这也是「改密即全端下线」的预期行为：用户应重新登录一次。
  Future<void> changePassword(String oldPassword, String newPassword) async {
    await ref
        .read(authRepositoryProvider)
        .changePassword(oldPassword, newPassword);
    await ref.read(tokenStorageProvider).clearAll();
    state = const AsyncData(null);
  }

  Future<void> _authenticate(Future<AuthResult> Function() action) async {
    state = const AsyncLoading();
    try {
      final auth = await action();
      await ref.read(tokenStorageProvider).write(auth.token);
      final refresh = auth.refreshToken;
      if (refresh != null && refresh.isNotEmpty) {
        await ref.read(tokenStorageProvider).writeRefresh(refresh);
      }
      state = AsyncData(auth.user);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
