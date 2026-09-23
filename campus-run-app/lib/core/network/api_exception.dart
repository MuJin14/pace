import 'package:dio/dio.dart';

/// 业务异常：由后端 `Result<T>` 的 `code != 0` 或网络错误映射而来。
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  /// 业务错误码（后端定义），网络类错误用 -1 兜底。
  final int code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';

  /// 把 [DioException] 转成 [ApiException]（含 401 → [UnauthorizedException]）。
  factory ApiException.fromDio(DioException e) {
    if (e.response?.statusCode == 401) {
      return const UnauthorizedException();
    }
    final data = e.response?.data;
    if (data is Map && data['code'] is int && data['code'] != 0) {
      final code = data['code'] as int;
      return ApiException(code, resolveErrorMessage(code, data['message'] as String? ?? '请求失败'));
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const ApiException(-1, '网络连接失败，请检查网络后重试');
    }
    return const ApiException(-1, '请求失败，请稍后重试');
  }
}

/// 未认证/登录过期，由拦截器清 token 后经 repository 抛出，authProvider 捕获后登出。
class UnauthorizedException extends ApiException {
  const UnauthorizedException() : super(401, '未认证或登录已过期');
}

const Map<int, String> _messages = {
  400: '参数错误',
  401: '未认证或登录已过期',
  403: '无权限',
  1001: '手机号已注册',
  1002: '用户不存在',
  1003: '密码错误',
  500: '服务器内部错误',
};

/// 已知错误码映射为友好中文，未知则用后端 message 兜底。
String resolveErrorMessage(int code, String fallback) =>
    _messages[code] ?? fallback;
