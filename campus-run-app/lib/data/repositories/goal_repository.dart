import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/api_util.dart';
import '../../core/network/dio_client.dart';
import '../models/goal.dart';

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  return GoalRepository(ref.read(dioProvider));
});

class GoalRepository {
  GoalRepository(this._dio);

  final Dio _dio;

  Future<List<Goal>> list() async {
    try {
      final resp = await _dio.get('/api/v1/goals');
      return unwrapList(resp).map((e) => Goal.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Goal> create({
    required String periodType,
    required int targetDistanceMeters,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final resp = await _dio.post('/api/v1/goals', data: {
        'periodType': periodType,
        'targetDistanceMeters': targetDistanceMeters,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      });
      return Goal.fromJson(unwrapMap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> cancel(int id) async {
    try {
      final resp = await _dio.delete('/api/v1/goals/$id');
      unwrapVoid(resp);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
