import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
    // 业务错误码不为 0 时必须留下「哪个请求 + 后端说了什么」，
    // 否则前端只显示一句「参数错误」，无法定位是哪个接口的参数不对。
    debugPrint('[业务错误] ${resp.requestOptions.uri} → code=$code message=${data['message']}');
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
