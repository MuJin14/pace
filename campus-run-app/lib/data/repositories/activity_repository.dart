import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/activity_detail.dart';
import '../models/activity_summary.dart';
import '../models/page_response.dart';
import '../models/track_point.dart';

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

  /// 创建运动记录（轨迹由后端重算距离/时长/配速），返回 activityId。
  Future<int> create({
    required int type,
    required int startTime,
    required int endTime,
    required List<TrackPoint> track,
    double? calories,
    /// 客户端计时器给出的**真实运动时长**（秒）。
    ///
    /// 为什么不能只靠 startTime/endTime：续接本地草稿继续跑时，
    /// 计时是累计的（一段段跑出来的），而「结束 − 开始」包含中间没在跑的空档。
    /// 服务端据此算出的时长会远大于真实运动时间 → 平均速度趋近 0
    /// → 被判「疑似原地漂移」→ 成绩作废。
    ///
    /// 服务端会校验它不超过轨迹的时间跨度，所以照实报即可。
    int? durationSeconds,
  }) async {
    try {
      final resp = await _dio.post('/api/v1/activity', data: {
        'type': type,
        'startTime': startTime,
        'endTime': endTime,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (calories != null) 'calories': calories,
        'track': track.map((p) => p.toJson()).toList(),
      });
      final data = _unwrap(resp);
      return (data['activityId'] as num).toInt();
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
