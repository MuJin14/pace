import 'package:campus_run_app/data/models/chat_message.dart';
import 'package:campus_run_app/features/friends/utils/chat_time_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

/// 聊天消息的 5 分钟分组。
///
/// **为什么要单测**：这是纯规则（间隔阈值 / 跨天 / 乱序），
/// 一旦写错，用户看到的是「时间分隔条乱插」或「隔了一天却没有任何标记」——
/// 属于体验上的硬伤，且在真机上要靠构造特定时间的数据才能复现。
void main() {
  /// 造一条消息，只关心时间戳。
  ChatMessage msg(int timestamp, {String content = 'hi'}) => ChatMessage(
        messageId: timestamp,
        senderId: 1,
        receiverId: 2,
        content: content,
        timestamp: timestamp,
      );

  /// 基准时间：2026-10-04 14:00:00（本地时间）
  final base = DateTime(2026, 10, 4, 14, 0, 0);
  int at(int minutes, {int seconds = 0}) =>
      base.add(Duration(minutes: minutes, seconds: seconds)).millisecondsSinceEpoch;

  group('groupMessagesByTime 分隔条插入规则', () {
    test('空列表返回空，不抛异常', () {
      expect(groupMessagesByTime(const []), isEmpty);
    });

    test('单条消息：前面总是有一条分隔条', () {
      final items = groupMessagesByTime([msg(at(0))]);

      expect(items, hasLength(2));
      expect(items[0], isA<ChatTimeSeparator>());
      expect(items[1], isA<ChatMessageItem>());
    });

    test('间隔 4 分 59 秒：不插分隔条（同一组）', () {
      final items = groupMessagesByTime([msg(at(0)), msg(at(4, seconds: 59))]);

      // 1 个分隔条 + 2 条消息
      expect(items, hasLength(3));
      expect(items.whereType<ChatTimeSeparator>(), hasLength(1));
    });

    test('间隔恰好 5 分钟：不插分隔条（边界取"大于"）', () {
      final items = groupMessagesByTime([msg(at(0)), msg(at(5))]);

      expect(items.whereType<ChatTimeSeparator>(), hasLength(1),
          reason: '边界值取「大于 5 分钟」才插，避免边界抖动');
    });

    test('间隔 5 分 01 秒：插入分隔条', () {
      final items = groupMessagesByTime([msg(at(0)), msg(at(5, seconds: 1))]);

      expect(items.whereType<ChatTimeSeparator>(), hasLength(2));
    });

    test('连续 10 条一分钟间隔：只有 1 个分隔条（开头那个）', () {
      final messages = List.generate(10, (i) => msg(at(i)));
      final items = groupMessagesByTime(messages);

      expect(items.whereType<ChatTimeSeparator>(), hasLength(1));
      expect(items.whereType<ChatMessageItem>(), hasLength(10));
    });

    test('时间乱序（后一条更早）也插分隔条，不让乱序数据绕过分组', () {
      final items = groupMessagesByTime([msg(at(10)), msg(at(0))]);

      expect(items.whereType<ChatTimeSeparator>(), hasLength(2));
    });

    test('自定义 gap 生效', () {
      final items = groupMessagesByTime(
        [msg(at(0)), msg(at(2))],
        gap: const Duration(minutes: 1),
      );
      expect(items.whereType<ChatTimeSeparator>(), hasLength(2));
    });

    test('条目顺序：分隔条紧跟在对应消息之前', () {
      final items = groupMessagesByTime([msg(at(0)), msg(at(10))]);

      expect(items[0], isA<ChatTimeSeparator>());
      expect((items[0] as ChatTimeSeparator).timestamp, at(0));
      expect(items[1], isA<ChatMessageItem>());
      expect(items[2], isA<ChatTimeSeparator>());
      expect((items[2] as ChatTimeSeparator).timestamp, at(10));
      expect(items[3], isA<ChatMessageItem>());
    });
  });

  group('formatChatSeparator 文案', () {
    test('今天只显示时分', () {
      final now = DateTime(2026, 10, 4, 20, 0);
      expect(formatChatSeparator(at(0), now: now), '14:00');
    });

    test('昨天加前缀', () {
      final now = DateTime(2026, 10, 5, 9, 0);
      expect(formatChatSeparator(at(0), now: now), '昨天 14:00');
    });

    test('前天加前缀', () {
      final now = DateTime(2026, 10, 6, 9, 0);
      expect(formatChatSeparator(at(0), now: now), '前天 14:00');
    });

    test('7 天内显示星期几', () {
      // 2026-10-04 是周日；2026-10-08 是周四
      final now = DateTime(2026, 10, 8, 9, 0);
      expect(formatChatSeparator(at(0), now: now), '周日 14:00');
    });

    test('同年超过 7 天显示月日', () {
      final now = DateTime(2026, 11, 20, 9, 0);
      expect(formatChatSeparator(at(0), now: now), '10月4日 14:00');
    });

    test('跨年显示年月日', () {
      final now = DateTime(2027, 3, 1, 9, 0);
      expect(formatChatSeparator(at(0), now: now), '2026年10月4日 14:00');
    });

    test('个位数时分补零', () {
      final now = DateTime(2026, 10, 4, 20, 0);
      final t = DateTime(2026, 10, 4, 9, 5).millisecondsSinceEpoch;
      expect(formatChatSeparator(t, now: now), '09:05');
    });
  });
}
