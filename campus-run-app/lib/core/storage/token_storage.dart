import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token 存储抽象：便于测试替换为内存实现，或将来加 Web 明文回退。
///
/// 双令牌：
/// - access token（{@link read}/{@link write}）随每个请求发送，有效期短；
/// - refresh token（{@link readRefresh}/{@link writeRefresh}）只用于换新 access token，有效期长。
abstract class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();

  /// 读取 refresh token（未登录或旧版本登录过则为 null/空）。
  Future<String?> readRefresh();

  /// 写入 refresh token。
  Future<void> writeRefresh(String token);

  /// 同时清空两类令牌（登出、或 refresh 失败需要重新登录时）。
  Future<void> clearAll();
}

/// 基于 flutter_secure_storage 的实现（Android Keystore / iOS Keychain 加密存储）。
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'auth_token';
  static const String _refreshKey = 'auth_refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);

  @override
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  @override
  Future<void> writeRefresh(String token) => _storage.write(key: _refreshKey, value: token);

  @override
  Future<void> clearAll() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _refreshKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());
