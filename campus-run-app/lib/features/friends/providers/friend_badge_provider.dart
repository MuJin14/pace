import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';

/// 「未读聊天消息」状态。
///
/// **为什么必须是「按好友计数」而不是一个布尔值**：
/// 只有一个 bool 时，界面只能显示「有未读」—— 用户回到社区页依然不知道
/// 是哪个人发的，必须挨个点开每个会话。微信的做法是在具体那一行挂红点，
/// 所以这里保存 `friendId -> 未读数`。
///
/// 未读数的来源有两条：WebSocket 实时到达的消息（[FriendBadgeNotifier.markMessage]），
/// 以及进入会话后的清空（[FriendBadgeNotifier.clearFriend]）。
/// 服务端没有「未读计数」接口，所以这里是**内存态** ——
/// 这正是它必须随账号重置的原因（见 [FriendBadgeNotifier.build]）。
///
/// 通知聚合（features/notifications/providers/notifications_provider.dart）
/// 会 watch 本 provider，把未读消息并入统一通知列表；
/// 聚合后是否显示红点请用 `hasNotificationsProvider`。
class FriendBadgeState {
  const FriendBadgeState({
    this.unreadByFriend = const {},
    this.ownerUserId,
  });

  /// 好友 id → 未读条数。只保留未读 > 0 的好友，可直接当红点数据源用。
  final Map<int, int> unreadByFriend;

  /// 这个红点属于哪个账号。切换账号时用来判断是否需要重置。
  final int? ownerUserId;

  /// 是否存在任何未读（社区 Tab / 通知页的圆点用它）。
  bool get hasUnreadMessage => unreadByFriend.isNotEmpty;

  /// 未读总数（角标上显示的数字）。
  int get totalUnread => unreadByFriend.values.fold(0, (sum, n) => sum + n);

  /// 某个好友的未读数；没有未读时为 0。
  int unreadOf(int friendId) => unreadByFriend[friendId] ?? 0;

  bool isUnread(int friendId) => unreadOf(friendId) > 0;

  FriendBadgeState copyWith({
    Map<int, int>? unreadByFriend,
    int? ownerUserId,
  }) =>
      FriendBadgeState(
        unreadByFriend: unreadByFriend ?? this.unreadByFriend,
        ownerUserId: ownerUserId ?? this.ownerUserId,
      );
}

final friendBadgeProvider =
    NotifierProvider<FriendBadgeNotifier, FriendBadgeState>(FriendBadgeNotifier.new);

class FriendBadgeNotifier extends Notifier<FriendBadgeState> {
  @override
  FriendBadgeState build() {
    // 订阅登录态：账号一变本 Notifier 就重建，红点自动清空。
    // 少了这一步会出现「B 登录后仍显示 A 的未读红点」——
    // 红点是全局内存状态，登出并不会清它。
    return FriendBadgeState(ownerUserId: ref.watchUserId());
  }

  /// 收到一条新消息。
  ///
  /// [friendId] 是**发送方**（即未读归属的会话）。传 null 时退化成
  /// 「有未读」占位（key 用 0，不是合法 userId，不会与真实好友冲突）——
  /// 这样旧调用点不传参数也能工作，不会漏掉红点。
  ///
  /// 刻意**不设上限**：用户需要知道积了多少条，界面上再决定是否显示成「99+」。
  void markMessage({int? friendId}) {
    final key = friendId ?? _anonymousKey;
    final next = Map<int, int>.from(state.unreadByFriend);
    next[key] = (next[key] ?? 0) + 1;
    state = state.copyWith(unreadByFriend: next);
  }

  /// 清空某个好友的未读（进入该会话时调用）。
  void clearFriend(int friendId) {
    if (!state.unreadByFriend.containsKey(friendId)) return;
    final next = Map<int, int>.from(state.unreadByFriend)..remove(friendId);
    state = state.copyWith(unreadByFriend: next);
  }

  /// 清空全部未读。
  void clearMessage() {
    if (state.unreadByFriend.isEmpty) return;
    state = state.copyWith(unreadByFriend: const {});
  }

  /// 用**服务端**返回的未读数重建红点。
  ///
  /// ⚠️ 这个方法补的是本 provider 的一个根本缺陷：
  /// 未读原本只靠 WebSocket 实时累加，是**纯内存态**。于是
  /// **设备离线期间收到的消息，登录后完全没有红点提示** ——
  /// 用户不知道有人给自己发过消息。
  ///
  /// 现在登录后、以及每次回到前台，都会拉一次服务端的未读数来重建。
  ///
  /// ## 快照语义（服务端约定）
  ///
  /// 服务端返回的是**完整快照**：所有好友都在里面，未读为 0 的给 0。
  /// 因此「不在响应里」就等于「没有未读」，可以直接把本地对应项去掉 ——
  /// 不去掉的话会积累**僵尸红点**：点进去读过了、切出去又冒出来。
  ///
  /// ## 取较大值而不是直接覆盖
  ///
  /// 服务端的未读在「消息落库」时确定，而本地计数可能已包含
  /// 刚通过 WebSocket 到达、服务端统计尚未反映的那一条；
  /// 直接覆盖会让用户刚看到的红点又消失。
  ///
  /// ⚠️ 调用方**只在拉取成功时**才调用本方法（失败时仓库返回 null，
  /// 见 MessageRepository.unreadCounts）。传一个「失败导致的空 Map」进来
  /// 会把用户已有的红点全部清掉。
  void mergeFromServer(Map<int, int> serverCounts) {
    final next = <int, int>{};
    serverCounts.forEach((friendId, count) {
      final local = state.unreadByFriend[friendId] ?? 0;
      final merged = count > local ? count : local;
      if (merged > 0) next[friendId] = merged;
    });
    // ⚠️ 这里**刻意丢掉**不在快照里的项（而不是保留）：
    // 它们要么已经被读过、要么用户已经读了但本地还没更新。
    // 保留会让红点永远清不掉。
    state = state.copyWith(unreadByFriend: next);
  }

  /// 未知发送方的占位 key（见 [markMessage]）。
  static const int _anonymousKey = 0;
}

/// 当前打开的好友聊天 id（null = 不在聊天页）。
///
/// **必须随账号重置**：它决定「新消息到达时算不算未读」。
/// 若切账号后仍保留上一个账号的好友 id，而对方恰好也是新账号的好友，
/// 新消息会被误判成「正在看这个会话」而**被吞掉** —— 表现为收到消息没有提醒。
final currentChatFriendIdProvider =
    NotifierProvider<CurrentChatFriendIdNotifier, int?>(
        CurrentChatFriendIdNotifier.new);

class CurrentChatFriendIdNotifier extends Notifier<int?> {
  @override
  int? build() {
    ref.watchUserId();
    return null;
  }

  /// 供外部只读访问当前值（`Notifier.state` 是 @protected，不能在 Notifier 外直接读）。
  int? get value => state;

  void set(int id) => state = id;

  void clear() => state = null;

  /// 仅当当前值等于 [id] 时清空，避免把后来进入的会话标记误清。
  void clearIf(int id) {
    if (state == id) state = null;
  }
}
