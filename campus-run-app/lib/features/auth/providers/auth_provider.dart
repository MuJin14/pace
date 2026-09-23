import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../../data/models/auth_result.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/auth_repository.dart';

/// 登录态：`AsyncValue<User?>`。
/// null = 未登录；非 null = 已登录。路由据此重定向。
final authProvider = AsyncNotifierProvider<AuthNotifier, User?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final token = await ref.read(tokenStorageProvider).read();
    if (token == null || token.isEmpty) return null;
    try {
      return await ref.read(authRepositoryProvider).me();
    } on UnauthorizedException {
      await ref.read(tokenStorageProvider).clear();
      return null;
    } catch (_) {
      // 网络等其它错误：暂按未登录处理（token 保留，避免误清）。
      return null;
    }
  }

  Future<void> login(String phone, String password) =>
      _authenticate(() => ref.read(authRepositoryProvider).login(phone, password));

  Future<void> register(String phone, String password, String nickname) =>
      _authenticate(() => ref.read(authRepositoryProvider).register(phone, password, nickname));

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(null);
  }

  Future<void> _authenticate(Future<AuthResult> Function() action) async {
    state = const AsyncLoading();
    try {
      final auth = await action();
      await ref.read(tokenStorageProvider).write(auth.token);
      state = AsyncData(auth.user);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
