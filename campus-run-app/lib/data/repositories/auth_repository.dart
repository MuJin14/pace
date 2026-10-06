import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/device_id_storage.dart';
import '../models/auth_result.dart';
import '../models/user.dart';
import '../models/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(dioProvider), ref.read(deviceIdStorageProvider));
});

class AuthRepository {
  AuthRepository(this._dio, this._deviceIds);

  final Dio _dio;

  /// 设备标识来源（见 DeviceIdStorage 的说明）。
  ///
  /// 登录时带给服务端，用来判断「是否换了一台设备」：
  /// 换了就把旧设备的令牌全部作废（单设备登录）。
  final DeviceIdStorage _deviceIds;

  Future<AuthResult> register(String phone, String password, String nickname) =>
      _post('/api/v1/auth/register', {
        'phone': phone,
        'password': password,
        'nickname': nickname,
      });

  Future<AuthResult> login(String phone, String password) async {
    // 设备标识读失败不影响登录：不带它服务端会退化成「每次都踢掉上一次登录」，
    // 属于可接受的降级（老客户端本来就是这个行为）。
    String? deviceId;
    try {
      deviceId = await _deviceIds.get();
    } catch (e) {
      debugPrint('[登录] 读取设备标识失败（不影响登录）: $e');
    }
    return _post('/api/v1/auth/login', {
      'phone': phone,
      'password': password,
      if (deviceId != null) 'deviceId': deviceId,
    });
  }

  Future<User> me() async {
    try {
      final resp = await _dio.get('/api/v1/user/me');
      return User.fromJson(_unwrap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 查看任意用户的公开主页（含与当前用户的关系）。
  Future<UserProfile> profile(int userId) async {
    try {
      final resp = await _dio.get('/api/v1/user/$userId/profile');
      return UserProfile.fromJson(_unwrap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 上传头像图片，返回可直接访问的 URL。
  ///
  /// 与 [updateProfile] 分开：上传只是「拿到一个地址」，是否设为头像由用户决定，
  /// 上传失败也不会把已有资料改坏。
  ///
  /// ⚠️ **必须用 `fromBytes`，不能用 `MultipartFile.fromFile`**：
  /// `fromFile` 依赖 `dart:io`，在 Web 上其构造函数直接抛
  /// `UnsupportedError("MultipartFile is only supported where dart:io is available.")`。
  /// 更隐蔽的是 dart2js 会因此把 `fromFile` 之后的所有代码判定为不可达，
  /// 把整个方法连同 URL 字符串一起 tree-shake 掉 —— 表现为「前端选了图却什么都
  /// 没发生，产物里也搜不到上传接口路径」。传字节则 Web / Android / iOS 都可用。
  Future<String> uploadAvatar(List<int> bytes, String filename) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final resp = await _dio.post('/api/v1/upload/avatar', data: form);
      return (_unwrap(resp)['url'] as String?) ?? '';
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 更新自己的资料（昵称 / 头像 / 性别 / 年龄及其可见性）。传 null 的字段表示不修改。
  ///
  /// ⚠️ 可见性用 `bool?` 而不是 `bool`：后端是 PATCH 语义，`null` = 不修改。
  /// 若用非空 `bool`，就无法表达「这次不改可见性」，会把用户之前的设置覆盖成 false。
  Future<User> updateProfile({
    String? nickname,
    String? avatarUrl,
    int? gender,
    int? age,
    bool? genderPublic,
    bool? agePublic,
  }) async {
    try {
      final resp = await _dio.put('/api/v1/user/me', data: {
        if (nickname != null) 'nickname': nickname,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (gender != null) 'gender': gender,
        if (age != null) 'age': age,
        if (genderPublic != null) 'genderPublic': genderPublic,
        if (agePublic != null) 'agePublic': agePublic,
      });
      return User.fromJson(_unwrap(resp));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 修改密码。需要提供当前密码。
  ///
  /// ⚠️ 服务端成功后会让**此前签发的所有 refresh token 失效**（改密即全端下线），
  /// 所以调用方必须清空本地令牌并回登录页 —— 否则 App 会拿着已失效的令牌
  /// 反复 401，表现为「一直转圈」。
  Future<void> changePassword(String oldPassword, String newPassword) async {
    try {
      final resp = await _dio.put('/api/v1/user/password', data: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      });
      _unwrap(resp);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 提交「忘记密码」申请（**不需要登录**）。
  ///
  /// ⚠️ 服务端对**未注册的手机号也返回成功** —— 这是刻意的：
  /// 如果这里能区分「该号未注册」，这个未登录接口就变成了
  /// 「哪些手机号注册过本 App」的批量探测工具。
  /// 所以前端**不能**把成功理解成「申请一定被受理」，文案要写成
  /// 「已提交，管理员会尽快处理」而不是「已找到你的账号」。
  Future<void> submitPasswordResetRequest(String phone, {String? note}) async {
    try {
      final resp = await _dio.post('/api/v1/password-reset-requests', queryParameters: {
        'phone': phone,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      _unwrap(resp);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 查看自己最近一次找回密码申请的处理状态。
  Future<Map<String, dynamic>?> myPasswordResetRequest() async {
    try {
      final resp = await _dio.get('/api/v1/password-reset-requests/mine');
      final data = _unwrap(resp);
      return data.isEmpty ? null : data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 注销账号（不可恢复）：服务端会级联删除该用户的全部数据。
  Future<void> deleteAccount() async {
    try {
      final resp = await _dio.delete('/api/v1/user/me');
      _unwrap(resp);
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
