import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/auth_result.dart';
import '../models/user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(dioProvider));
});

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<AuthResult> register(String phone, String password, String nickname) =>
      _post('/api/v1/auth/register', {
        'phone': phone,
        'password': password,
        'nickname': nickname,
      });

  Future<AuthResult> login(String phone, String password) =>
      _post('/api/v1/auth/login', {'phone': phone, 'password': password});

  Future<User> me() async {
    try {
      final resp = await _dio.get('/api/v1/user/me');
      return User.fromJson(_unwrap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthResult> _post(String path, Map<String, dynamic> data) async {
    try {
      final resp = await _dio.post(path, data: data);
      return AuthResult.fromJson(_unwrap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 解包统一返回体 `Result<T>`：`code == 0` 取 `data`，否则抛 [ApiException]。
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
