import 'package:campus_run_app/features/friends/providers/chat_preference_provider.dart';
import 'package:campus_run_app/features/friends/providers/friend_badge_provider.dart';
import 'package:campus_run_app/features/friends/utils/notify_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红点行为的回归测试。
///
/// ## 规则（用户定的）
///
/// > **只在你点进会话之后红点才消失；否则一来新消息就显示红点。**
///
/// 红点只由两件事决定：
///   1. 来了新消息 → `markMessage` 立刻 +1；
///   2. 点进那个会话 → `clearFriend` 清零。
///
/// ## 为什么要改成这样（真实故障）
///
/// 原实现加完红点后又判一次「正在看这个会话」就把它清掉 ——
/// 于是红点是否显示取决于 `currentChatFriendId` **准不准**。
/// 而它出过问题：只在进入会话时被 `set`、从来没被清空，
/// App 便一直以为你还在看那个会话，**之后所有消息的红点都被立刻清掉**。
///
/// 用户的原话：「我在线时发消息就不显示红点，非要清掉后台再进就显示了」——
/// 后半句能亮，正是因为重启后 `currentChat` 是 null。
///
/// 现在红点不再依赖那个状态：判「是否正在看」只用来决定**要不要弹通知**。
void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  /// 复刻 app.dart 里 `_handleIncomingMessage` 的**新**逻辑。
  ///
  /// 刻意照抄真实分支顺序，否则测的不是线上那份。
  void onIncoming(
    ProviderContainer c, {
    required int senderId,
    required int myUserId,
  }) {
    if (senderId == myUserId) return; // 自己发的
    if (myUserId == 0) return; // 未登录

    // 红点：无条件加
    c.read(friendBadgeProvider.notifier).markMessage(friendId: senderId);

    // 提醒方式（不影响红点）
    decideNotifyAction(NotifyContext(
      senderId: senderId,
      myUserId: myUserId,
      currentChatFriendId: c.read(currentChatFriendIdProvider),
      mutedFriendIds: c.read(mutedFriendIdsProvider).value ?? const <int>{},
      appInForeground: true,
    ));
  }

  /// 复刻「点进会话」时的行为（chat_page.initState）。
  void onEnterChat(ProviderContainer c, int friendId) {
    c.read(currentChatFriendIdProvider.notifier).set(friendId);
    c.read(friendBadgeProvider.notifier).clearFriend(friendId);
  }

  /// 复刻「退出会话」时的行为（chat_page.dispose）。
  ///
  /// 两件事都要做，缺一不可：
  ///   · clearFriend：把在这个会话里新收到、但你**已经看过**的消息的红点清掉；
  ///   · clearIf    ：清「当前会话」标记，否则之后该好友的消息会被判成
  ///                  「已在眼前」而不弹通知。
  void onExitChat(ProviderContainer c, int friendId) {
    c.read(friendBadgeProvider.notifier).clearFriend(friendId);
    c.read(currentChatFriendIdProvider.notifier).clearIf(friendId);
  }

  group('红点规则：只在点进会话后消失', () {
    test('核心：收到新消息就亮红点（在线、不在任何会话里）', () {
      final c = makeContainer();
      onIncoming(c, senderId: 4, myUserId: 1);
      expect(c.read(friendBadgeProvider).unreadOf(4), 1);
    });

    test('核心：即使「正在看这个会话」，收到消息也照样加红点', () {
      // 这正是原实现会吞掉红点的地方 —— currentChat 说你正在看，
      // 于是加完立刻清掉。现在不再这样。
      final c = makeContainer();
      c.read(currentChatFriendIdProvider.notifier).set(4);

      onIncoming(c, senderId: 4, myUserId: 1);

      expect(
        c.read(friendBadgeProvider).unreadOf(4),
        1,
        reason: '「是否正在看这个会话」只该决定要不要弹通知，'
            '不该决定红点的有无 —— 否则 currentChat 一旦不准，红点就永远不亮',
      );
    });

    test('核心：点进会话后红点才清零', () {
      final c = makeContainer();
      onIncoming(c, senderId: 4, myUserId: 1);
      onIncoming(c, senderId: 4, myUserId: 1);
      expect(c.read(friendBadgeProvider).unreadOf(4), 2);

      onEnterChat(c, 4); // 用户点进会话

      expect(c.read(friendBadgeProvider).unreadOf(4), 0);
    });

    test('点进 A 的会话不会清掉 B 的红点', () {
      final c = makeContainer();
      onIncoming(c, senderId: 4, myUserId: 1);
      onIncoming(c, senderId: 7, myUserId: 1);

      onEnterChat(c, 4);

      expect(c.read(friendBadgeProvider).unreadOf(4), 0);
      expect(c.read(friendBadgeProvider).unreadOf(7), 1);
    });

    test('离开会话后收到消息仍然亮红点（用户报的场景）', () {
      final c = makeContainer();
      onEnterChat(c, 4); // 进会话
      onExitChat(c, 4); // 退出会话

      onIncoming(c, senderId: 4, myUserId: 1);

      expect(c.read(friendBadgeProvider).unreadOf(4), 1);
    });

    test('⚠️ 退出会话时红点也要清掉（会话里收到的已看过）', () {
      // 用户追加要求：「如果退出聊天界面红点也该消失」。
      // 场景：在会话里时对方又发了一条 → 红点 +1；
      // 用户看完了返回列表 → 那一行不该还挂着红点。
      final c = makeContainer();
      onEnterChat(c, 4);

      onIncoming(c, senderId: 4, myUserId: 1); // 会话里收到新消息 → 红点 +1
      expect(c.read(friendBadgeProvider).unreadOf(4), 1);

      onExitChat(c, 4); // 看完返回列表

      expect(
        c.read(friendBadgeProvider).unreadOf(4),
        0,
        reason: '退出会话时红点不清 → 用户看到刚读过的消息还挂着红点，'
            '误以为还有没读的',
      );
    });

    test('⚠️ 退出会话后 currentChat 标记也要清（否则之后不弹通知）', () {
      final c = makeContainer();
      onEnterChat(c, 4);
      onExitChat(c, 4);

      expect(c.read(currentChatFriendIdProvider), isNull);
    });

    test('退出 A 的会话不影响 B 的红点', () {
      final c = makeContainer();
      onIncoming(c, senderId: 7, myUserId: 1); // B 有未读
      onEnterChat(c, 4);
      onExitChat(c, 4);

      expect(c.read(friendBadgeProvider).unreadOf(7), 1);
    });

    test('currentChat 陈旧（没被清掉）也不再影响红点', () {
      // 修复前后最本质的差别：以前 currentChat 一旦陈旧，红点就永远不亮；
      // 现在它只影响「弹不弹通知」。
      final c = makeContainer();
      c.read(currentChatFriendIdProvider.notifier).set(4); // 陈旧：用户其实已离开

      onIncoming(c, senderId: 4, myUserId: 1);

      expect(c.read(friendBadgeProvider).unreadOf(4), 1);
    });

    test('自己发的消息不加红点（多端同步场景）', () {
      final c = makeContainer();
      onIncoming(c, senderId: 1, myUserId: 1);
      expect(c.read(friendBadgeProvider).hasUnreadMessage, isFalse);
    });

    test('未登录时不加红点', () {
      final c = makeContainer();
      onIncoming(c, senderId: 4, myUserId: 0);
      expect(c.read(friendBadgeProvider).hasUnreadMessage, isFalse);
    });
  });

  group('⚠️ 用户 id 0 是合法用户（迁移 006 后的管理员）', () {
    // 这一组守的是真实故障的根因，务必保留。
    //
    // 迁移 006 把管理员重排为 id 0/1/2 之前，用户 id 从 1 开始，
    // 所以 `myUserId == 0` 可以安全地当「未登录」哨兵。
    // 迁移之后 0 成了**真实用户**，那条判断对 0 号用户恒成立：
    // 他收到的每条实时消息都被当成「未登录」而静默丢弃 ——
    // **红点永远不亮、通知永远不弹**，且不报错、日志安静。
    //
    // 现在「未登录」用 kUnknownUserId(-1) 表示，0 是正常 id。

    test('decideNotifyAction 对 myUserId=0 不能返回 none', () {
      const action = NotifyAction.vibrateAndNotify;
      final actual = decideNotifyAction(const NotifyContext(
        senderId: 4,
        myUserId: 0, // 真实的 0 号用户，不是「未登录」
        currentChatFriendId: null,
        mutedFriendIds: {},
        appInForeground: true,
      ));
      expect(
        actual,
        action,
        reason: '0 号用户收到的消息被判为 none → 红点不亮、通知不弹。'
            '「未登录」必须用 kUnknownUserId(-1) 判断，不能用 0',
      );
    });

    test('kUnknownUserId 是负数，不可能与真实用户 id 冲突', () {
      expect(kUnknownUserId, lessThan(0));
    });

    test('真正未登录（kUnknownUserId）时才返回 none', () {
      final actual = decideNotifyAction(const NotifyContext(
        senderId: 4,
        myUserId: kUnknownUserId,
        currentChatFriendId: null,
        mutedFriendIds: {},
        appInForeground: true,
      ));
      expect(actual, NotifyAction.none);
    });

    test('0 号用户自己发的消息仍然不提醒（多端同步）', () {
      final actual = decideNotifyAction(const NotifyContext(
        senderId: 0,
        myUserId: 0,
        currentChatFriendId: null,
        mutedFriendIds: {},
        appInForeground: true,
      ));
      expect(actual, NotifyAction.none);
    });
  });

  group('通知方式仍按原策略（与红点解耦）', () {
    // myUserId 必须用真实非 0 值：decideNotifyAction 里
    // 「未登录（myUserId == 0）不提醒」是一条真实规则，传 0 会让断言恒为 none。
    NotifyAction actionFor(ProviderContainer c, int senderId, int myId) =>
        decideNotifyAction(NotifyContext(
          senderId: senderId,
          myUserId: myId,
          currentChatFriendId: c.read(currentChatFriendIdProvider),
          mutedFriendIds: const <int>{},
          appInForeground: true,
        ));

    test('正在看这个会话 -> none（不弹通知，但红点照样有）', () {
      final c = makeContainer();
      c.read(currentChatFriendIdProvider.notifier).set(4);
      expect(actionFor(c, 4, 1), NotifyAction.none);
    });

    test('不在该会话 -> 震动+通知', () {
      final c = makeContainer();
      expect(actionFor(c, 4, 1), NotifyAction.vibrateAndNotify);
    });

    test('免打扰 -> 只给红点', () {
      final action = decideNotifyAction(const NotifyContext(
        senderId: 4,
        myUserId: 1,
        currentChatFriendId: null,
        mutedFriendIds: {4},
        appInForeground: true,
      ));
      expect(action, NotifyAction.badgeOnly);
    });
  });

  group('markMessage / clearFriend 基本语义', () {
    test('按好友分开累计', () {
      final c = makeContainer();
      final n = c.read(friendBadgeProvider.notifier);
      n.markMessage(friendId: 4);
      n.markMessage(friendId: 4);
      n.markMessage(friendId: 7);

      final s = c.read(friendBadgeProvider);
      expect(s.unreadOf(4), 2);
      expect(s.unreadOf(7), 1);
      expect(s.totalUnread, 3);
      expect(s.hasUnreadMessage, isTrue);
    });

    test('mergeFromServer 用服务端快照重建（快照外的项丢弃）', () {
      final c = makeContainer();
      final n = c.read(friendBadgeProvider.notifier);
      n.markMessage(friendId: 4);
      n.markMessage(friendId: 7);

      n.mergeFromServer({4: 1});

      final s = c.read(friendBadgeProvider);
      expect(s.unreadOf(4), 1);
      expect(s.unreadOf(7), 0, reason: '快照外要丢弃，否则留下僵尸红点');
    });
  });
}
