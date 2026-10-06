import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/api_util.dart';
import '../../core/network/dio_client.dart';
import '../models/chat_message.dart';
import '../models/page_response.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.read(dioProvider));
});

class MessageRepository {
  MessageRepository(this._dio);

  final Dio _dio;

  Future<PageResponse<ChatMessage>> history(
    int friendId, {
    int? beforeId,
    int size = 20,
  }) async {
    try {
      final resp = await _dio.get('/api/v1/message/history', queryParameters: {
        'friendId': friendId,
        if (beforeId != null) 'beforeId': beforeId,
        'size': size,
      });
      return PageResponse.fromJson(unwrapMap(resp), ChatMessage.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 上传聊天图片，返回可直接访问的 URL。
  ///
  /// 与发送消息分开：上传失败时**不产生任何消息**，
  /// 比先插一条永远加载不出来的图片消息好得多。
  ///
  /// ⚠️ 必须用 `MultipartFile.fromBytes`：`fromFile` 在 Web 上直接抛异常，
  /// 且 dart2js 会把整个方法 tree-shake 掉（详见 AGENTS.md）。
  Future<String> uploadChatImage(List<int> bytes, String filename) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final resp = await _dio.post('/api/v1/upload/chat-image', data: form);
      return (unwrapMap(resp)['url'] as String?) ?? '';
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 当前用户的未读消息数（按发送方分组）。
  ///
  /// **为什么需要（真实故障）**：未读红点原本只靠 WebSocket 实时累加，
  /// 是纯内存态。设备离线（或被顶下线）期间收到的消息，登录后
  /// **完全没有红点提示** —— 用户不知道有人给自己发过消息。
  ///
  /// 返回值的语义很关键：
  ///   · **成功** → Map（**可能是空 Map**，表示确实没有任何未读）；
  ///   · **失败** → null。
  ///
  /// ⚠️ 两者必须区分：把失败也当成空 Map 返回的话，一次网络抖动
  /// 就会把用户已有的红点全部清掉；反过来把空 Map 当成失败，
  /// 已经读过的红点就永远清不掉。所以用可空类型而不是空集合兜底。
  ///
  /// 服务端返回的是**完整快照**（所有好友都在，未读为 0 给 0），
  /// 因此「不在响应里」就等于没有未读。
  Future<Map<int, int>?> unreadCounts() async {
    try {
      final resp = await _dio.get('/api/v1/message/unread');
      final data = resp.data;
      if (data is! Map || data['code'] != 0) return null;
      final payload = data['data'];
      if (payload is! Map) return null;
      final result = <int, int>{};
      payload.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id == null) return;
        final n = v is num ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) result[id] = n;
      });
      return result;
    } catch (e) {
      debugPrint('[未读] 拉取未读数失败: $e');
      return null;
    }
  }

}
