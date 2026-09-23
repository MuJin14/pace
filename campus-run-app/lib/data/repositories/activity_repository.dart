import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/activity_detail.dart';
import '../models/activity_summary.dart';
import '../models/page_response.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(ref.read(dioProvider));
});

class ActivityRepository {
  ActivityRepository(this._dio);

  final Dio _dio;

  /// 分页查询当前用户的运动记录（按 start_time 倒序）。
  Future<PageResponse<ActivitySummary>> page({
    int page = 1,
    int size = 20,
    int? type,
  }) async {
    try {
      final resp = await _dio.get('/api/v1/activity', queryParameters: {
        'page': page,
        'size': size,
        if (type != null) 'type': type,
      });
      final data = _unwrap(resp);
      return PageResponse.fromJson(data, ActivitySummary.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 查询单条运动记录详情（含轨迹与卡路里）。
  Future<ActivityDetail> detail(int id) async {
    try {
      final resp = await _dio.get('/api/v1/activity/$id');
      return ActivityDetail.fromJson(_unwrap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Map<String, dynamic> _unwrap(Response resp) {
    final data = resp.data;
    if (data is! Map<String, dynamic>) {
      throw const ApiException(-1, '响应格式错误');
    }
    final code = data['code'];
    if (code != 0) {
      final c = code is int ? code : -1;
      throw ApiException(c, resolveErrorMessage(c, data['message'] as String? ?? '请求失败'));
    }
    return (data['data'] as Map<String, dynamic>?) ?? const {};
  }
}
