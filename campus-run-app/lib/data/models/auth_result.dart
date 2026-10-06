import 'user.dart';

/// 登录/注册成功返回：token + 用户信息（后端将二者平铺在 `data` 字段中）。
class AuthResult {
  const AuthResult({
    required this.token,
    this.refreshToken,
    required this.user,
  });

  /// access token：随请求发送，有效期短。
  final String token;

  /// refresh token：用于自动续期，有效期长。
  /// 可为 null —— 兼容尚未升级 refresh 机制的后端。
  final String? refreshToken;

  final User user;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: json['token'] as String,
      refreshToken: json['refreshToken'] as String?,
      user: User.fromJson(json),
    );
  }
}
