import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/api_util.dart';
import '../../core/network/dio_client.dart';
import '../models/leaderboard_entry.dart';
import '../models/my_rank.dart';
import '../models/page_response.dart';

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(ref.read(dioProvider));
});

class LeaderboardRepository {
  LeaderboardRepository(this._dio);

  final Dio _dio;

  Future<PageResponse<LeaderboardEntry>> board({
    required String scope,
    required int type,
    String? period,
    int page = 1,
    int size = 50,
  }) async {
    try {
      final resp = await _dio.get('/api/v1/leaderboard', queryParameters: {
        'scope': scope,
        'type': type,
        if (period != null) 'period': period,
        'page': page,
        'size': size,
      });
      return PageResponse.fromJson(unwrapMap(resp), LeaderboardEntry.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<MyRank> myRank({
    required String scope,
    required int type,
    String? period,
  }) async {
    try {
      final resp = await _dio.get('/api/v1/leaderboard/my-rank', queryParameters: {
        'scope': scope,
        'type': type,
        if (period != null) 'period': period,
      });
      return MyRank.fromJson(unwrapMap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
