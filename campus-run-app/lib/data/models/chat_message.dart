/// 聊天消息。
class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = 1,
    this.delivered = 0,
    required this.timestamp,
  });

  final int messageId;
  final int senderId;
  final int receiverId;
  final String content;
  final int type;
  final int delivered;

  /// 毫秒时间戳
  final int timestamp;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: (json['messageId'] as num).toInt(),
      senderId: (json['senderId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      content: json['content'] as String,
      type: (json['type'] as num?)?.toInt() ?? 1,
      delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num).toInt(),
    );
  }
}
