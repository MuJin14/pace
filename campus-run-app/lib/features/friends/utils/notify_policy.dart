/// 新消息到达时「要不要提醒」的纯决策逻辑。
///
/// **为什么抽成纯函数**：提醒规则涉及「是不是我发的 / 是不是当前会话 /
/// 有没有免打扰 / App 在不在前台」四个条件的组合，共十几种情况。
/// 写成页面里的 if 串起来既测不到也容易改错，
/// 而这条链路的 bug 用户感知极强（该响不响 = 漏消息；不该响乱响 = 被打扰）。
library;

/// 收到一条消息时的上下文。所有字段都由调用方在**收到消息的那一刻**取快照。
class NotifyContext {
  const NotifyContext({
    required this.senderId,
    required this.myUserId,
    required this.currentChatFriendId,
    required this.mutedFriendIds,
    required this.appInForeground,
  });

  /// 消息发送方。
  final int senderId;

  /// 当前登录用户 id；未登录时为 0。
  final int myUserId;

  /// 当前打开的会话对方 id；不在聊天页时为 null。
  final int? currentChatFriendId;

  /// 已设置免打扰的会话对方 id 集合。
  final Set<int> mutedFriendIds;

  /// App 是否在前台（可见）。
  ///
  /// 后台时**也返回 true**：那时用户看不到聊天页，更需要通知。
  /// 这个字段目前只用于将来「后台时连震动也要更明显」之类的策略，
  /// 保留是为了让调用方必须显式表态，而不是漏掉这个维度。
  final bool appInForeground;
}

/// 提醒方式（按强度递增）。
enum NotifyAction {
  /// 完全不提醒（连红点也不必额外处理 —— 红点由未读数统一驱动）。
  none,

  /// 只更新未读红点，不震动不弹通知。
  badgeOnly,

  /// 震动 + 系统通知 + 红点。
  vibrateAndNotify,
}

/// 判断该用哪种方式提醒。
///
/// 规则（顺序即优先级）：
/// 1. **自己发的消息不提醒** —— 多端登录时自己发的消息会同步回来，
///    给自己弹「新消息」是明显的错误。
/// 2. **正在看这个会话 → 不提醒**：消息已经显示在眼前了，
///    再震动就是重复打扰（微信同样如此）。
/// 3. **该会话免打扰 → 只走红点**：用户要的是「别弹通知」，
///    不是「别让我知道有消息」—— 所以红点仍然要给。
/// 4. 其余情况：震动 + 通知 + 红点。
NotifyAction decideNotifyAction(NotifyContext ctx) {
  // 1. 自己发的（多端同步场景）
  if (ctx.senderId == ctx.myUserId) return NotifyAction.none;

  // 2. 未登录：没有「我的账号」可言，不提醒
  if (ctx.myUserId == 0) return NotifyAction.none;

  // 3. 正在看这个会话
  if (ctx.currentChatFriendId != null &&
      ctx.currentChatFriendId == ctx.senderId) {
    return NotifyAction.none;
  }

  // 4. 免打扰：保留红点，但不打扰
  if (ctx.mutedFriendIds.contains(ctx.senderId)) {
    return NotifyAction.badgeOnly;
  }

  return NotifyAction.vibrateAndNotify;
}

/// 通知标题/正文的构造（纯函数，便于单测）。
///
/// [type] 与后端 `MessageType` 一致：1=文本 2=图片 3=表情包。
/// 媒体消息必须给可读占位，否则通知栏会出现一条**空白通知**。
({String title, String body}) buildNotificationContent({
  required String senderNickname,
  required String? content,
  int type = 1,
}) {
  final body = switch (type) {
    2 => '[图片]',
    3 => '[表情]',
    _ => (content == null || content.trim().isEmpty) ? '[消息]' : content.trim(),
  };
  return (title: senderNickname.isEmpty ? '新消息' : senderNickname, body: body);
}
