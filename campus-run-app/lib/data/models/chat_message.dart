/// 聊天消息。
class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = 1,
    this.mediaUrl,
    this.delivered = 0,
    this.readAt,
    this.failed = false,
    required this.timestamp,
    this.senderNickname,
  });

  final int messageId;
  final int senderId;
  final int receiverId;

  /// 文本内容。媒体消息（图片/表情包）可以为空字符串。
  final String content;

  /// 消息类型：1=文本 2=图片 3=表情包。与后端 `MessageType` 一致。
  final int type;

  /// 媒体地址：type=2/3 时非空。
  final String? mediaUrl;

  final int delivered;

  /// 对端已读时间（毫秒时间戳，null = 未读；后端 ChatMessageResponse.readAt）
  final int? readAt;

  /// 本地乐观发送失败标记（仅前端，不入库）。
  final bool failed;

  /// 毫秒时间戳
  final int timestamp;

  /// 发送者昵称（服务端下发）。
  ///
  /// ⚠️ 通知标题**必须**用它，不要再去查好友列表：好友列表要等用户
  /// 进过社区页才加载，冷启动后收到的第一条消息查不到昵称，
  /// 通知就只能显示「新消息」——用户看到通知却不知道是谁发的。
  ///
  /// 老服务端不下发这个字段时为 null，调用方回退到「新消息」。
  final String? senderNickname;

  /// 是否图片消息。
  bool get isImage => type == 2;

  /// 是否表情包消息。
  bool get isSticker => type == 3;

  /// 是否文本消息。
  bool get isText => type == 1;

  /// 会话列表/通知里的一行摘要：媒体消息用可读占位，避免出现空白。
  String get preview => switch (type) {
        2 => '[图片]',
        3 => '[表情]',
        _ => content,
      };

  ChatMessage copyWith({
    int? messageId,
    int? readAt,
    bool? failed,
    int? type,
    String? mediaUrl,
    String? content,
    String? senderNickname,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      senderId: senderId,
      receiverId: receiverId,
      content: content ?? this.content,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      delivered: delivered,
      readAt: readAt ?? this.readAt,
      failed: failed ?? this.failed,
      timestamp: timestamp,
      // ⚠️ 必须带上。漏掉它会让「经过一次 copyWith 的消息」丢掉昵称 ——
      // 发送中 → 已送达 正好走这条路，于是通知标题退化成「新消息」。
      // 这类字段漏传**不会编译报错**，只会静默丢数据，所以有对应测试守着。
      senderNickname: senderNickname ?? this.senderNickname,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: (json['messageId'] as num).toInt(),
      senderId: (json['senderId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      // content 可空（图片/表情消息）：兜底成空串，避免渲染时到处判 null
      content: (json['content'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 1,
      mediaUrl: json['mediaUrl'] as String?,
      delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      readAt: (json['readAt'] as num?)?.toInt(),
      timestamp: (json['timestamp'] as num).toInt(),
      // 服务端下发的发送者昵称（通知标题用它，见 senderNickname 的说明）。
      // 空白串规整成 null：避免通知标题变成一串空格。
      senderNickname: (json['senderNickname'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['senderNickname'] as String).trim(),
    );
  }
}
