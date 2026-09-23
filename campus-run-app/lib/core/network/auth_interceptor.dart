import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// 只做两件事：请求时注入 token；收到 401 时清除本地 token。
/// 401 如何变成 [UnauthorizedException] 由 repository 的 `ApiException.fromDio` 统一处理，
/// 这里不反向依赖 authProvider，避免循环依赖。
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenStorage);

  final TokenStorage _tokenStorage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokenStorage.read();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      unawaited(_tokenStorage.clear());
    }
    handler.next(err);
  }
}
