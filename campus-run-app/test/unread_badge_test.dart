import 'package:campus_run_app/data/models/chat_message.dart';
import 'package:campus_run_app/features/friends/providers/friend_badge_provider.dart';
import 'package:campus_run_app/features/friends/utils/notify_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 未读红点的三个真实缺陷（用户连续反馈）。
///
/// 1. **切 Tab 就清空** —— 点「社区」时调过 `clearMessage()`，
///    而红点的语义是「这条消息你还没读」。看一眼好友列表不等于读过。
/// 2. **离线消息登录后很久才出现** —— 需要服务端同步来重建。
/// 3. **通知标题看不出是谁** —— 昵称只能从好友列表查，而那个列表
///    要等用户进过社区页才加载。
///
/// 这些都是「看起来能用、细节上让人困惑」的问题，不会抛异常，
/// 所以必须靠断言钉住。
void main() {
  group('红点状态', () {
    test('服务端数据能重建红点（离线消息登录后必须出现）', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      // 模拟登录：账号 id 决定红点归属
      c.read(friendBadgeProvider);
      c.read(friendBadgeProvider.notifier).mergeFromServer({42: 3});

      expect(c.read(friendBadgeProvider).unreadOf(42), 3,
          reason: '服务端说有 3 条未读，红点就该出现');
      expect(c.read(friendBadgeProvider).hasUnreadMessage, isTrue);
    });

    test('合并取较大值：不会把刚通过 WebSocket 到达的红点覆盖掉', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final n = c.read(friendBadgeProvider.notifier);
      n.markMessage(friendId: 42); // 本地 +1
      n.markMessage(friendId: 42); // 本地 +1（共 2）

      // 服务端此刻只统计到 1 条（第 2 条刚落库/还没统计）
      n.mergeFromServer({42: 1});

      expect(c.read(friendBadgeProvider).unreadOf(42), 2,
          reason: '直接覆盖会让用户刚看到的红点又消失');
    });

    test('服务端清零后，本地没有新消息的项会被去掉', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final n = c.read(friendBadgeProvider.notifier);
      n.markMessage(friendId: 7);
      n.markMessage(friendId: 8);
      expect(c.read(friendBadgeProvider).totalUnread, 2);

      // 7 已被读（服务端不再返回），8 仍未读
      n.mergeFromServer({8: 1, 9: 1});

      final s = c.read(friendBadgeProvider);
      expect(s.unreadOf(7), 0, reason: '服务端已清零的项应当消失');
      expect(s.unreadOf(8), 1);
      expect(s.unreadOf(9), 1, reason: '服务端新出现的未读要加进来');
    });

    test('进入会话只清那一个好友，不影响其他好友', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final n = c.read(friendBadgeProvider.notifier);
      n.mergeFromServer({7: 2, 8: 3});
      n.clearFriend(7);

      final s = c.read(friendBadgeProvider);
      expect(s.unreadOf(7), 0);
      expect(s.unreadOf(8), 3, reason: '读了一个会话不该清掉别人的红点');
    });

    test('快照里没有的项会被清掉（否则积累僵尸红点）', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final n = c.read(friendBadgeProvider.notifier);
      n.mergeFromServer({7: 2, 8: 1});
      // 下一次快照只有 8：说明 7 已经读过了
      n.mergeFromServer({8: 1});

      expect(c.read(friendBadgeProvider).unreadOf(7), 0,
          reason: '不在快照里 = 没有未读，必须清掉');
      expect(c.read(friendBadgeProvider).unreadOf(8), 1);
    });
  });

  group('通知标题（必须能看出是谁发的）', () {
    test('有昵称时标题就是昵称', () {
      final r = buildNotificationContent(
        senderNickname: '张三',
        content: '在吗',
      );
      expect(r.title, '张三');
      expect(r.body, '在吗');
    });

    test('昵称为空时回退到「新消息」，而不是空标题', () {
      final r = buildNotificationContent(senderNickname: '', content: '在吗');
      expect(r.title, '新消息');
      expect(r.title, isNotEmpty);
    });

    test('图片/表情消息的正文是可读占位', () {
      expect(
          buildNotificationContent(
              senderNickname: '张三', content: null, type: 2)
              .body,
          '[图片]');
      expect(
          buildNotificationContent(
              senderNickname: '张三', content: null, type: 3)
              .body,
          '[表情]');
    });
  });

  group('消息模型解析昵称', () {
    test('服务端下发的 senderNickname 被解析出来', () {
      final m = ChatMessage.fromJson({
        'messageId': 1,
        'senderId': 42,
        'receiverId': 7,
        'content': '在吗',
        'type': 1,
        'delivered': 0,
        'timestamp': 1700000000000,
        'senderNickname': '张三',
      });
      expect(m.senderNickname, '张三',
          reason: '通知标题会用这个字段，解析不到就只剩「新消息」');
    });

    test('老服务端不下发该字段时为 null（回退到查好友列表）', () {
      final m = ChatMessage.fromJson({
        'messageId': 1,
        'senderId': 42,
        'receiverId': 7,
        'content': '在吗',
        'type': 1,
        'delivered': 0,
        'timestamp': 1700000000000,
      });
      expect(m.senderNickname, isNull);
    });

    test('空白昵称被规整成 null（避免标题出现一串空格）', () {
      final m = ChatMessage.fromJson({
        'messageId': 1,
        'senderId': 42,
        'receiverId': 7,
        'content': '在吗',
        'type': 1,
        'delivered': 0,
        'timestamp': 1700000000000,
        'senderNickname': '   ',
      });
      expect(m.senderNickname, isNull);
    });
  });
}
