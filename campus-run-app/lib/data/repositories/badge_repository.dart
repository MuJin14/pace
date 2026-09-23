import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/api_util.dart';
import '../../core/network/dio_client.dart';
import '../models/badge.dart';
import '../models/user_badge.dart';

final badgeRepositoryProvider = Provider<BadgeRepository>((ref) {
  return BadgeRepository(ref.read(dioProvider));
});

class BadgeRepository {
  BadgeRepository(this._dio);

  final Dio _dio;

  Future<List<Badge>> all() async {
    try {
      final resp = await _dio.get('/api/v1/badges');
      return unwrapList(resp).map((e) => Badge.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<UserBadge>> mine() async {
    try {
      final resp = await _dio.get('/api/v1/badges/mine');
      return unwrapList(resp).map((e) => UserBadge.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
