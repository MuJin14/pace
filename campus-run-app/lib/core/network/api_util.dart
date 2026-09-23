import 'package:dio/dio.dart';

import 'api_exception.dart';

/// 统一返回体 `Result<T>` 解包工具：`code == 0` 取 `data`，否则抛 [ApiException]。
/// 与各 repository 内联的 `_unwrap` 等价，供新增接口复用。

Map<String, dynamic> unwrapMap(Response resp) {
  final data = resp.data;
  if (data is! Map<String, dynamic>) {
    throw const ApiException(-1, '响应格式错误');
  }
  final code = data['code'];
  if (code != 0) {
    throw ApiException(
      code is int ? code : -1,
      resolveErrorMessage(code is int ? code : -1, data['message'] as String? ?? '请求失败'),
    );
  }
  return (data['data'] as Map<String, dynamic>?) ?? const {};
}

List<dynamic> unwrapList(Response resp) {
  final data = resp.data;
  if (data is! Map<String, dynamic>) {
    throw const ApiException(-1, '响应格式错误');
  }
  final code = data['code'];
  if (code != 0) {
    throw ApiException(
      code is int ? code : -1,
      resolveErrorMessage(code is int ? code : -1, data['message'] as String? ?? '请求失败'),
    );
  }
  return (data['data'] as List<dynamic>?) ?? const [];
}

/// 仅校验业务码，不关心 `data` 内容（用于 `data: null` 的写操作）。
void unwrapVoid(Response resp) {
  final data = resp.data;
  if (data is! Map<String, dynamic>) {
    throw const ApiException(-1, '响应格式错误');
  }
  final code = data['code'];
  if (code != 0) {
    throw ApiException(
      code is int ? code : -1,
      resolveErrorMessage(code is int ? code : -1, data['message'] as String? ?? '请求失败'),
    );
  }
}
