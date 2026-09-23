import 'package:dio/dio.dart';
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
}
