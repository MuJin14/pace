import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';

/// 鉴权拦截器：注入 access token；遇到 401 自动用 refresh token 换新并重放请求。
///
/// 设计要点：
/// 1. **单飞（single-flight）刷新**：多个请求同时 401 时只发起一次刷新，
///    其余请求等待同一个 Future。否则 N 个并发请求会打出 N 次刷新，
///    既浪费又是天然的重放攻击面。
/// 2. **专用 Dio**：刷新请求用一个不带本拦截器的裸 Dio 发出，
///    避免「刷新失败 → 再加拦截器 → 再刷新」的递归。
/// 3. **只重放一次**：通过 [_retriedKey] 标记，防止服务端持续 401 时无限重试。
/// 4. **降级安全**：没有 refresh token、或刷新被拒（401/403），
///    清空全部令牌回到未登录态，让用户重新登录，而不是把请求卡死。
///
/// 这里不反向依赖 authProvider，避免循环依赖；令牌清空后由
/// `AuthNotifier` 的 401 分支负责把登录态置为 null（路由据此跳登录页）。
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenStorage);

  final TokenStorage _tokenStorage;

  /// 标记「本次请求已经重放过」，避免无限递归。
  static const String _retriedKey = '_campusRunRetried';

  /// 正在进行的刷新（单飞）。
  Future<String?>? _refreshInFlight;

  /// 刷新令牌用的裸客户端（不挂本拦截器）。
  static final Dio _refreshDio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokenStorage.read();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final options = err.requestOptions;
    final alreadyRetried = options.extra[_retriedKey] == true;

    if (status != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    // ── 单设备登录：被别的设备顶下线时，**不要**去刷新令牌 ──
    //
    // 服务端在版本不符时返回 401 + code=4011。此时 refresh token 同样是
    // 旧版本的，刷新一定失败 —— 白跑一次网络往返，而且刷新失败又会清空令牌，
    // 用户看到的还是「登录已过期」，白白多等一次超时。
    //
    // 直接清掉本地令牌返回，让上层按「已在其他设备登录」提示并回登录页。
    final body = err.response?.data;
    if (body is Map && body['code'] == 4011) {
      debugPrint('[鉴权] 服务端返回 4011：账号已在其他设备登录，清除本地令牌');
      await _tokenStorage.clearAll();
      handler.next(err);
      return;
    }

    final refreshToken = await _tokenStorage.readRefresh();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _tokenStorage.clearAll();
      handler.next(err);
      return;
    }

    final newAccess = await _refreshAccessToken(refreshToken);
    if (newAccess == null || newAccess.isEmpty) {
      await _tokenStorage.clearAll();
      handler.next(err);
      return;
    }

    try {
      options.extra[_retriedKey] = true;
      options.headers['Authorization'] = 'Bearer $newAccess';
      final response = await _retryDio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// 单飞刷新：并发调用共享同一个 Future。
  Future<String?> _refreshAccessToken(String refreshToken) {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _doRefresh(refreshToken);
    _refreshInFlight = future;
    // 完成后释放，允许后续（新的一轮）再次刷新。
    unawaited(future.whenComplete(() {
      _refreshInFlight = null;
    }));
    return future;
  }

  Future<String?> _doRefresh(String refreshToken) async {
    try {
      final resp = await _refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = resp.data;
      if (body == null || body['code'] != 0) {
        return null;
      }
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final access = data['token'] as String?;
      final rotatedRefresh = data['refreshToken'] as String?;
      if (access == null || access.isEmpty) {
        return null;
      }
      await _tokenStorage.write(access);
      // 后端目前原样返回 refresh token；若将来改成轮换，这里会自动跟上。
      if (rotatedRefresh != null && rotatedRefresh.isNotEmpty) {
        await _tokenStorage.writeRefresh(rotatedRefresh);
      }
      return access;
    } on DioException {
      return null;
    }
  }

  /// 重放请求用的客户端（同样不挂拦截器，避免再次进入本逻辑）。
  static final Dio _retryDio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
}
