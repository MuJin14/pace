import 'dart:convert';

/// WebSocket 事件类型，与后端 `WsMessage.type` 字符串对齐。
enum WsEventType {
  message('message'),
  readReceipt('read_receipt'),
  friendRequest('friend_request'),
  friendAccepted('friend_accepted'),
  friendDeleted('friend_deleted'),
  heartbeat('heartbeat'),
  pong('pong'),
  ack('ack'),
  error('error');

  const WsEventType(this.raw);

  final String raw;

  static WsEventType? fromRaw(String? raw) {
    for (final t in values) {
      if (t.raw == raw) return t;
    }
    return null;
  }
}

/// WebSocket 信封：`{type, data}`。`data` 可为 null（如 pong）。
class WsMessage {
  const WsMessage({required this.type, this.data});

  final WsEventType type;
  final Map<String, dynamic>? data;

  /// 解析一帧文本，非法 JSON 或未知 type 返回 null（由调用方跳过）。
  static WsMessage? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = WsEventType.fromRaw(decoded['type'] as String?);
      if (type == null) return null;
      final data = decoded['data'];
      return WsMessage(
        type: type,
        data: data is Map<String, dynamic> ? data : null,
      );
    } catch (_) {
      return null;
    }
  }
}
