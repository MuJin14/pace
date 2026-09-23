import 'user.dart';

/// 登录/注册成功返回：token + 用户信息（后端将二者平铺在 `data` 字段中）。
class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final User user;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: json['token'] as String,
      user: User.fromJson(json),
    );
  }
}
