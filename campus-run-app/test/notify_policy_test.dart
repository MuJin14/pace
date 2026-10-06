import 'package:campus_run_app/features/friends/utils/notify_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 消息提醒的决策规则。
///
/// 这条链路的 bug 用户感知极强：
/// - **该响不响** → 漏消息，用户以为对方没回
/// - **不该响乱响** → 正在聊天时一直震动，或者自己发的消息弹自己
///
/// 所以把四种条件的组合全部固化成测试。
void main() {
  /// 构造上下文：默认「B 给我发消息，我不在聊天页，没设免打扰」。
  NotifyContext ctx({
    int senderId = 2,
    int myUserId = 1,
    int? currentChatFriendId,
    Set<int>? mutedFriendIds,
    bool appInForeground = true,
  }) =>
      NotifyContext(
        senderId: senderId,
        myUserId: myUserId,
        currentChatFriendId: currentChatFriendId,
        mutedFriendIds: mutedFriendIds ?? const {},
        appInForeground: appInForeground,
      );

  group('decideNotifyAction 基础分支', () {
    test('别人发来、不在该会话、未免打扰 → 震动 + 通知', () {
      expect(decideNotifyAction(ctx()), NotifyAction.vibrateAndNotify);
    });

    test('自己发的消息 → 不提醒（多端登录时自己发的会同步回来）', () {
      expect(
        decideNotifyAction(ctx(senderId: 1, myUserId: 1)),
        NotifyAction.none,
        reason: '给自己弹「新消息」是明显错误',
      );
    });

    test('正在看这个会话 → 不提醒（消息已经显示在眼前）', () {
      expect(
        decideNotifyAction(ctx(currentChatFriendId: 2)),
        NotifyAction.none,
      );
    });

    test('正在看**别的**会话 → 仍然提醒', () {
      expect(
        decideNotifyAction(ctx(senderId: 3, currentChatFriendId: 2)),
        NotifyAction.vibrateAndNotify,
        reason: '只有当前会话才静默，别的会话该响还得响',
      );
    });

    // ⚠️ 这条原来写的是 myUserId=0，**编码了一个错误的前提**：
    // 迁移 006 之后 0 是合法用户 id（管理员），「未登录」必须用
    // kUnknownUserId(-1) 表示。保留 0 会让 0 号用户收不到任何提醒 ——
    // 那正是「消息到了但红点不亮」的根因。
    test('未登录（kUnknownUserId）→ 不提醒', () {
      expect(decideNotifyAction(ctx(myUserId: kUnknownUserId)),
          NotifyAction.none);
    });

    test('⚠️ myUserId=0 是真实用户，必须正常提醒', () {
      expect(decideNotifyAction(ctx(myUserId: 0)),
          NotifyAction.vibrateAndNotify);
    });
  });

  group('免打扰', () {
    test('该会话免打扰 → 只走红点，不震动', () {
      expect(
        decideNotifyAction(ctx(mutedFriendIds: {2})),
        NotifyAction.badgeOnly,
        reason: '免打扰是「别打扰我」，不是「别让我知道」—— 红点仍要给',
      );
    });

    test('免打扰的是别人，不影响这条 → 正常提醒', () {
      expect(
        decideNotifyAction(ctx(senderId: 2, mutedFriendIds: {5, 9})),
        NotifyAction.vibrateAndNotify,
      );
    });

    test('正在看这个会话时即使未免打扰也不提醒（优先级更高）', () {
      expect(
        decideNotifyAction(ctx(currentChatFriendId: 2, mutedFriendIds: {})),
        NotifyAction.none,
      );
    });

    test('正在看这个会话 + 已免打扰 → 不提醒（两个条件都指向静默）', () {
      expect(
        decideNotifyAction(ctx(currentChatFriendId: 2, mutedFriendIds: {2})),
        NotifyAction.none,
      );
    });
  });

  group('优先级顺序', () {
    test('自己发的消息优先级最高：即使不在聊天页、未免打扰也不提醒', () {
      expect(
        decideNotifyAction(ctx(
          senderId: 1,
          myUserId: 1,
          currentChatFriendId: null,
          mutedFriendIds: const {},
        )),
        NotifyAction.none,
      );
    });

    test('未登录优先于免打扰判断', () {
      expect(
        decideNotifyAction(
            ctx(myUserId: kUnknownUserId, mutedFriendIds: {2})),
        NotifyAction.none,
      );
    });
  });

  group('buildNotificationContent', () {
    test('文本消息用原文', () {
      final r = buildNotificationContent(senderNickname: 'TesterB', content: '在吗');
      expect(r.title, 'TesterB');
      expect(r.body, '在吗');
    });

    test('图片消息用 [图片] 占位（否则通知栏空白）', () {
      final r = buildNotificationContent(
        senderNickname: 'TesterB',
        content: null,
        type: 2,
      );
      expect(r.body, '[图片]');
    });

    test('表情消息用 [表情] 占位', () {
      final r = buildNotificationContent(
        senderNickname: 'TesterB',
        content: null,
        type: 3,
      );
      expect(r.body, '[表情]');
    });

    test('文本消息内容为空时兜底为 [消息]，不留空白', () {
      final r = buildNotificationContent(senderNickname: 'TesterB', content: '   ');
      expect(r.body, '[消息]');
    });

    test('昵称缺失时标题兜底为「新消息」', () {
      final r = buildNotificationContent(senderNickname: '', content: 'hi');
      expect(r.title, '新消息');
    });

    test('文本消息前后空白被裁掉', () {
      final r = buildNotificationContent(senderNickname: '甲', content: '  你好  ');
      expect(r.body, '你好');
    });
  });
}
