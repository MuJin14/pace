import '../../../../data/models/chat_message.dart';

/// 聊天列表里的一项：要么是一条消息，要么是一条时间分隔条。
///
/// 用密封类而不是「在消息里塞一个 showTime 字段」：
/// 分隔条与消息的渲染完全不同的 widget，混在一个模型里会让
/// build 方法里到处是 `if (item.showTime)` 分支。
sealed class ChatDisplayItem {
  const ChatDisplayItem();
}

/// 一条消息。
class ChatMessageItem extends ChatDisplayItem {
  const ChatMessageItem(this.message);

  final ChatMessage message;
}

/// 一条时间分隔条。
class ChatTimeSeparator extends ChatDisplayItem {
  const ChatTimeSeparator(this.timestamp);

  /// 该分隔条代表的时间（毫秒时间戳）。
  final int timestamp;
}

/// 相邻消息间隔超过该阈值就插入时间分隔条。
///
/// 5 分钟是主流 IM 的惯例：太短会让连续对话被切碎，
/// 太长则「隔了几小时再聊」看起来像同一段对话。
const Duration kChatTimeGap = Duration(minutes: 5);

/// 把消息列表按时间间隔分组，返回可直接渲染的条目序列。
///
/// **纯函数**：输入相同则输出相同，不读时钟、不碰 UI。
/// 时间格式化需要「现在」时由调用方传入 [now]，
/// 这样单测可以固定时间点，不会因为跑测试的时刻不同而失败。
///
/// 规则：
/// - 第一条消息**总是**带一个分隔条（会话开头要能看到起始时间）
/// - 相邻两条消息间隔 **> 5 分钟**时，在后者前面插入分隔条
/// - 恰好等于 5 分钟**不插入**（边界取「大于」，避免边界抖动）
/// - 时间倒序（后一条早于前一条）时也插入分隔条：
///   历史记录按倒序加载，乱序数据不应让分隔逻辑失效
///
/// [messages] 按时间**升序**（旧 → 新），与聊天页底部对齐的展示顺序一致。
List<ChatDisplayItem> groupMessagesByTime(
  List<ChatMessage> messages, {
  Duration gap = kChatTimeGap,
}) {
  if (messages.isEmpty) return const [];

  final items = <ChatDisplayItem>[];
  int? previousTimestamp;

  for (final message in messages) {
    final needsSeparator = previousTimestamp == null ||
        message.timestamp - previousTimestamp > gap.inMilliseconds ||
        message.timestamp < previousTimestamp;

    if (needsSeparator) {
      items.add(ChatTimeSeparator(message.timestamp));
    }
    items.add(ChatMessageItem(message));
    previousTimestamp = message.timestamp;
  }

  return items;
}

/// 把分隔条的时间戳格式化成微信风格的文案。
///
/// [now] 由调用方传入，便于单测固定时间点。
String formatChatSeparator(int timestamp, {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final thatDay = DateTime(time.year, time.month, time.day);
  final clock = '${_two(time.hour)}:${_two(time.minute)}';

  final diffDays = today.difference(thatDay).inDays;

  if (diffDays == 0) {
    return clock;
  }
  if (diffDays == 1) {
    return '昨天 $clock';
  }
  if (diffDays == 2) {
    return '前天 $clock';
  }
  // 本周内（7 天内）显示星期几
  if (diffDays > 0 && diffDays < 7) {
    return '${_weekday(time.weekday)} $clock';
  }
  // 同一年只显示月日
  if (time.year == current.year) {
    return '${time.month}月${time.day}日 $clock';
  }
  return '${time.year}年${time.month}月${time.day}日 $clock';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _weekday(int weekday) => switch (weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      _ => '周日',
    };
