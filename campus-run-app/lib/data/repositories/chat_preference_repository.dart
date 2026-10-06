import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
final chatPreferenceRepositoryProvider = Provider<ChatPreferenceRepository>((ref) {
  return ChatPreferenceRepository(ref.read(dioProvider));
});

/// 会话偏好（免打扰）。
///
/// 免打扰是**单向、按会话**的：A 静音 B 的消息提醒，不影响 B 是否收到 A 的提醒。
/// 服务端语义详见后端 `ChatPreferenceController`。
class ChatPreferenceRepository {
  ChatPreferenceRepository(this._dio);

  final Dio _dio;

  /// 自己被静音的会话对方 id 列表。
  ///
  /// ⚠️ 这里**不能复用 `unwrapMap`**：它把 `data` 断言成 `Map`，
  /// 而本接口的 `data` 是**数组**（`{"code":0,"data":[1,2]}`）。
  /// 走 `unwrapMap` 会直接抛「响应格式错误」。
  Future<List<int>> mutedFriendIds() async {
    try {
      final resp = await _dio.get('/api/v1/chat/preference/muted');
      final body = resp.data;
      if (body is! Map) {
        throw const ApiException(-1, '响应格式错误');
      }
      final code = body['code'];
      if (code != 0) {
        final c = code is int ? code : -1;
        throw ApiException(
          c,
          resolveErrorMessage(c, body['message'] as String? ?? '请求失败'),
        );
      }
      final data = body['data'];
      if (data is! List) return const [];
      return data.map((e) => (e as num).toInt()).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 设置或取消对某个会话的免打扰（幂等）。
  Future<void> setMuted(int friendId, bool muted) async {
    try {
      final resp = await _dio.put('/api/v1/chat/preference', queryParameters: {
        'friendId': friendId,
        'muted': muted,
      });
      final body = resp.data;
      if (body is Map && body['code'] != 0) {
        final c = body['code'];
        final code = c is int ? c : -1;
        throw ApiException(
          code,
          resolveErrorMessage(code, body['message'] as String? ?? '请求失败'),
        );
      }
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
