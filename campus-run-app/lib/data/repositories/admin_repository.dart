import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/api_util.dart';
import '../../core/network/dio_client.dart';
import '../models/admin_user.dart';
import '../models/password_reset_request.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.read(dioProvider));
});

/// 管理后台接口（找回密码 / 用户查询）。
///
/// 所有接口都要求服务端的 `ROLE_ADMIN`。前端把入口藏起来只是 UI 便利，
/// **不是安全边界** —— 真正的校验在 `@PreAuthorize`。
class AdminRepository {
  AdminRepository(this._dio);

  final Dio _dio;

  /// 分页查询用户。[keyword] 可匹配手机号 / 昵称 / 专属 ID。
  Future<({List<AdminUser> list, int total})> listUsers({
    String? keyword,
    int page = 1,
    int size = 20,
  }) async {
    try {
      final resp = await _dio.get('/api/v1/admin/users', queryParameters: {
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        'page': page,
        'size': size,
      });
      final data = unwrapMap(resp);
      final list = (data['list'] as List? ?? const [])
          .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
          .toList();
      return (list: list, total: (data['total'] as num?)?.toInt() ?? 0);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 直接重置某个用户的密码，返回**一次性**临时密码。
  ///
  /// ⚠️ 临时密码只在这次响应里出现：服务端只存 BCrypt 哈希，之后无法再读回。
  /// 调用方必须当场展示给管理员，否则只能再重置一次。
  Future<({int userId, String nickname, String temporaryPassword})> resetPassword(
    int userId,
  ) async {
    try {
      final resp = await _dio.post('/api/v1/admin/users/$userId/reset-password');
      final data = unwrapMap(resp);
      return (
        userId: (data['userId'] as num?)?.toInt() ?? userId,
        nickname: (data['nickname'] as String?) ?? '',
        temporaryPassword: (data['temporaryPassword'] as String?) ?? '',
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 找回密码申请列表。[status] 为 null 时返回全部（0=待处理 1=已重置 2=已拒绝）。
  Future<List<PasswordResetRequestItem>> listRequests({int? status}) async {
    try {
      final resp = await _dio.get('/api/v1/admin/password-reset-requests',
          queryParameters: {if (status != null) 'status': status});
      return unwrapList(resp)
          .map((e) => PasswordResetRequestItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 处理申请：重置密码并标记为已重置，返回一次性临时密码。
  Future<({int userId, String nickname, String temporaryPassword})> resolveRequest(
    int requestId,
  ) async {
    try {
      final resp =
          await _dio.post('/api/v1/admin/password-reset-requests/$requestId/resolve');
      final data = unwrapMap(resp);
      return (
        userId: (data['userId'] as num?)?.toInt() ?? 0,
        nickname: (data['nickname'] as String?) ?? '',
        temporaryPassword: (data['temporaryPassword'] as String?) ?? '',
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 拒绝申请（申请人无法证明账号归属时）。
  Future<void> rejectRequest(int requestId) async {
    try {
      final resp =
          await _dio.post('/api/v1/admin/password-reset-requests/$requestId/reject');
      unwrapMap(resp);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
