import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/api_util.dart';
import '../../core/network/dio_client.dart';
import '../models/friend_item.dart';
import '../models/friend_request.dart';
import '../models/page_response.dart';
import '../models/user_brief.dart';

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(ref.read(dioProvider));
});

class FriendRepository {
  FriendRepository(this._dio);

  final Dio _dio;

  Future<List<FriendItem>> list() async {
    try {
      final resp = await _dio.get('/api/v1/friend/list');
      return unwrapList(resp).map((e) => FriendItem.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<FriendRequest>> requests() async {
    try {
      final resp = await _dio.get('/api/v1/friend/requests');
      return unwrapList(resp).map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<PageResponse<UserBrief>> search(String keyword, {int page = 1, int size = 20}) async {
    try {
      final resp = await _dio.get('/api/v1/friend/search', queryParameters: {
        'keyword': keyword,
        'page': page,
        'size': size,
      });
      return PageResponse.fromJson(unwrapMap(resp), UserBrief.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> sendRequest(int targetUserId) =>
      _void(() => _dio.post('/api/v1/friend/request', data: {'targetUserId': targetUserId}));

  Future<void> accept(int requestId) =>
      _void(() => _dio.post('/api/v1/friend/accept', data: {'requestId': requestId}));

  Future<void> reject(int requestId) =>
      _void(() => _dio.post('/api/v1/friend/reject', data: {'requestId': requestId}));

  Future<void> delete(int friendId) =>
      _void(() => _dio.delete('/api/v1/friend/$friendId'));

  Future<void> _void(Future<Response> Function() action) async {
    try {
      final resp = await action();
      unwrapVoid(resp);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
