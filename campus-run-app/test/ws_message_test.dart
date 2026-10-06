import 'package:campus_run_app/core/ws/ws_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// WebSocket 信封解析单元测试：类型映射、未知类型与非法 JSON 容错。
void main() {
  group('WsEventType', () {
    test('raw 字符串与后端 ws 协议一致且无重复', () {
      expect(WsEventType.values.length, 9);
      expect(WsEventType.message.raw, 'message');
      expect(WsEventType.readReceipt.raw, 'read_receipt');
      expect(WsEventType.friendRequest.raw, 'friend_request');
      expect(WsEventType.friendAccepted.raw, 'friend_accepted');
      expect(WsEventType.friendDeleted.raw, 'friend_deleted');
      expect(WsEventType.heartbeat.raw, 'heartbeat');
      expect(WsEventType.pong.raw, 'pong');
      expect(WsEventType.ack.raw, 'ack');
      expect(WsEventType.error.raw, 'error');
      expect(
        WsEventType.values.map((e) => e.raw).toSet().length,
        WsEventType.values.length,
      );
    });

    test('fromRaw 命中已知类型', () {
      expect(WsEventType.fromRaw('message'), WsEventType.message);
      expect(WsEventType.fromRaw('read_receipt'), WsEventType.readReceipt);
      expect(WsEventType.fromRaw('friend_accepted'), WsEventType.friendAccepted);
      expect(WsEventType.fromRaw('error'), WsEventType.error);
    });

    test('fromRaw 对 null / 空串 / 未知 / 大小写不符返回 null', () {
      expect(WsEventType.fromRaw(null), isNull);
      expect(WsEventType.fromRaw(''), isNull);
      expect(WsEventType.fromRaw('unknown_event'), isNull);
      expect(WsEventType.fromRaw('MESSAGE'), isNull);
      expect(WsEventType.fromRaw('read-receipt'), isNull);
      expect(WsEventType.fromRaw(' message'), isNull);
    });
  });

  group('WsMessage.tryParse', () {
    test('解析 type + data', () {
      final m = WsMessage.tryParse(
          '{"type":"message","data":{"messageId":1,"content":"hi"}}');
      expect(m, isNotNull);
      expect(m!.type, WsEventType.message);
      expect(m.data, isA<Map<String, dynamic>>());
      expect(m.data!['messageId'], 1);
      expect(m.data!['content'], 'hi');
    });

    test('无 data 字段（pong）时 data 为 null', () {
      final m = WsMessage.tryParse('{"type":"pong"}');
      expect(m, isNotNull);
      expect(m!.type, WsEventType.pong);
      expect(m.data, isNull);
    });

    test('data 为 null 时保持 null', () {
      final m = WsMessage.tryParse('{"type":"pong","data":null}');
      expect(m, isNotNull);
      expect(m!.data, isNull);
    });

    test('data 不是对象（数组/字符串/数字）时置为 null', () {
      expect(WsMessage.tryParse('{"type":"pong","data":[1,2]}')!.data, isNull);
      expect(WsMessage.tryParse('{"type":"pong","data":"x"}')!.data, isNull);
      expect(WsMessage.tryParse('{"type":"pong","data":3}')!.data, isNull);
    });

    test('read_receipt 的批量 messageIds 原样保留', () {
      final m = WsMessage.tryParse(
          '{"type":"read_receipt","data":{"readerId":2,"friendId":1,'
          '"messageIds":[10,11,12],"readAt":1695456000000}}');
      expect(m!.type, WsEventType.readReceipt);
      expect(m.data!['readerId'], 2);
      expect(m.data!['messageIds'], [10, 11, 12]);
      expect(m.data!['readAt'], 1695456000000);
    });

    test('未知 type 返回 null（调用方跳过该帧）', () {
      expect(WsMessage.tryParse('{"type":"unknown_event","data":{}}'), isNull);
      expect(WsMessage.tryParse('{"type":"","data":{}}'), isNull);
    });

    test('缺失 / 非字符串 / null 的 type 返回 null', () {
      expect(WsMessage.tryParse('{"data":{"a":1}}'), isNull);
      expect(WsMessage.tryParse('{"type":null}'), isNull);
      expect(WsMessage.tryParse('{"type":123}'), isNull);
      expect(WsMessage.tryParse('{"type":["message"]}'), isNull);
    });

    test('非法 JSON 返回 null 且不抛异常', () {
      expect(WsMessage.tryParse(''), isNull);
      expect(WsMessage.tryParse('not json'), isNull);
      expect(WsMessage.tryParse('{"type":"message"'), isNull);
    });

    test('JSON 顶层不是对象时返回 null', () {
      expect(WsMessage.tryParse('[1,2,3]'), isNull);
      expect(WsMessage.tryParse('"message"'), isNull);
      expect(WsMessage.tryParse('42'), isNull);
      expect(WsMessage.tryParse('null'), isNull);
      expect(WsMessage.tryParse('true'), isNull);
    });

    test('额外字段被忽略', () {
      final m = WsMessage.tryParse(
          '{"type":"ack","data":{"ok":true},"extra":"ignored"}');
      expect(m!.type, WsEventType.ack);
      expect(m.data!['ok'], isTrue);
      expect(m.data!.containsKey('extra'), isFalse);
    });

    test('构造的常量消息可直接比较字段', () {
      const m = WsMessage(type: WsEventType.heartbeat);
      expect(m.type, WsEventType.heartbeat);
      expect(m.data, isNull);
    });
  });
}
