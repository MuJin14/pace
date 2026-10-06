import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/repositories/chat_preference_repository.dart';

/// 自己被静音的会话对方 id 集合。
///
/// **必须随账号重建**（`watchUserId`）：免打扰是「我」的设置，
/// 同一设备 A 退出、B 登录后若沿用缓存，B 会继承 A 的静音名单 ——
/// 表现是「新账号莫名其妙收不到某个人的消息提醒」。
final mutedFriendIdsProvider =
    AsyncNotifierProvider<MutedFriendIdsNotifier, Set<int>>(
  MutedFriendIdsNotifier.new,
);

class MutedFriendIdsNotifier extends AsyncNotifier<Set<int>> {
  @override
  Future<Set<int>> build() async {
    // 未登录直接返回空集合，不发必然 401 的请求
    if (ref.watchUserId() == null) return const {};
    final ids = await ref.read(chatPreferenceRepositoryProvider).mutedFriendIds();
    return ids.toSet();
  }

  /// 切换某个会话的免打扰，**乐观更新**：
  /// 立即改本地状态让开关响应跟手，失败再回滚并抛错。
  Future<void> toggle(int friendId, bool muted) async {
    final previous = state.value ?? const <int>{};
    final next = {...previous};
    if (muted) {
      next.add(friendId);
    } else {
      next.remove(friendId);
    }
    state = AsyncData(next);

    try {
      await ref.read(chatPreferenceRepositoryProvider).setMuted(friendId, muted);
    } catch (e) {
      // 回滚：不能让界面显示成功但服务端没生效
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// 某会话是否免打扰（供消息提醒判断，同步读取）。
  bool isMuted(int friendId) => (state.value ?? const <int>{}).contains(friendId);
}
