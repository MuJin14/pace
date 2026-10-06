import 'package:campus_run_app/data/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// 富媒体消息模型（type / mediaUrl）。
///
/// **为什么必须测**：图片与表情消息的 `content` 是空的。
/// 如果模型把 `content` 当必填非空解析，服务端返回的图片消息会**直接抛异常**，
/// 整个会话打不开 —— 这不是「少显示一个字符」，是聊天记录整个加载失败。
void main() {
  Map<String, dynamic> base() => {
        'messageId': 1,
        'senderId': 2,
        'receiverId': 1,
        'timestamp': 1700000000000,
      };

  group('ChatMessage 富媒体字段', () {
    test('图片消息：content 为 null 时不抛异常，兜底为空串', () {
      final msg = ChatMessage.fromJson({
        ...base(),
        'content': null,
        'type': 2,
        'mediaUrl': 'http://x/a.jpg',
      });

      expect(msg.isImage, isTrue);
      expect(msg.isText, isFalse);
      expect(msg.content, '', reason: 'content 必须兜底成空串，不能让渲染层判 null');
      expect(msg.mediaUrl, 'http://x/a.jpg');
    });

    test('图片消息：完全缺失 content 字段也能解析', () {
      final msg = ChatMessage.fromJson({
        ...base(),
        'type': 2,
        'mediaUrl': 'http://x/a.jpg',
      });

      expect(msg.content, '');
      expect(msg.isImage, isTrue);
    });

    test('表情包消息：type=3', () {
      final msg = ChatMessage.fromJson({
        ...base(),
        'type': 3,
        'mediaUrl': 'asset:happy.png',
      });

      expect(msg.isSticker, isTrue);
      expect(msg.isImage, isFalse);
      expect(msg.mediaUrl, 'asset:happy.png');
    });

    test('文本消息：type 缺失时默认 1', () {
      final msg = ChatMessage.fromJson({...base(), 'content': '你好'});

      expect(msg.isText, isTrue);
      expect(msg.type, 1);
      expect(msg.mediaUrl, isNull);
    });

    test('文本消息：content 显式为 null 时也不崩', () {
      // 后端 content 列已改为可空；即使文本消息理论上不该为空，
      // 解析层也不应该因为脏数据直接崩掉整个历史列表。
      final msg = ChatMessage.fromJson({...base(), 'content': null});

      expect(msg.content, '');
      expect(msg.isText, isTrue);
    });
  });

  group('preview（通知 / 会话摘要文案）', () {
    test('图片用 [图片] 占位，避免空白', () {
      final msg = ChatMessage.fromJson({
        ...base(),
        'type': 2,
        'mediaUrl': 'http://x/a.jpg',
      });
      expect(msg.preview, '[图片]');
    });

    test('表情包用 [表情] 占位', () {
      final msg = ChatMessage.fromJson({
        ...base(),
        'type': 3,
        'mediaUrl': 'asset:s.png',
      });
      expect(msg.preview, '[表情]');
    });

    test('文本用原文', () {
      final msg = ChatMessage.fromJson({...base(), 'content': '在吗'});
      expect(msg.preview, '在吗');
    });
  });

  group('copyWith 保留媒体字段', () {
    test('标记失败/已读不会丢掉 type 与 mediaUrl', () {
      final msg = ChatMessage.fromJson({
        ...base(),
        'type': 2,
        'mediaUrl': 'http://x/a.jpg',
      });

      final failed = msg.copyWith(failed: true);
      expect(failed.type, 2, reason: '重试路径必须还是图片消息，不能退化成文本');
      expect(failed.mediaUrl, 'http://x/a.jpg');
      expect(failed.failed, isTrue);

      final read = msg.copyWith(readAt: 123);
      expect(read.type, 2);
      expect(read.mediaUrl, 'http://x/a.jpg');
      expect(read.readAt, 123);
    });
  });
}
