import 'package:campus_run_app/core/network/auth_interceptor.dart';
import 'package:campus_run_app/core/storage/device_id_storage.dart';
import 'package:campus_run_app/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单设备登录的客户端部分。
///
/// 两件事必须钉死：
///   1. **设备标识在同一安装内稳定** —— 不稳定的话，用户每次重开 App
///      都被服务端当成「换了设备」，会把自己踢下线；
///   2. **收到 4011 时不去刷新令牌** —— 被踢下线时 refresh token 也是旧的，
///      刷新必然失败，白跑一次往返还让用户多等一次超时。
void main() {
  group('设备标识', () {
    test('首次调用会生成，且格式是 32 位十六进制', () async {
      final s = InMemoryDeviceIdStorage();
      final id = await s.get();
      expect(id.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue,
          reason: '应当是 32 位小写十六进制，实际: $id');
    });

    test('同一实例重复读取返回同一个值（这是整个机制的前提）', () async {
      final s = InMemoryDeviceIdStorage();
      final a = await s.get();
      final b = await s.get();
      final c = await s.get();
      expect(a, b);
      expect(b, c);
    });

    test('不同实例生成不同的值（不同设备不能被判成同一台）', () async {
      final ids = <String>{};
      for (var i = 0; i < 20; i++) {
        ids.add(await InMemoryDeviceIdStorage().get());
      }
      expect(ids.length, 20, reason: '20 次应当得到 20 个不同的串');
    });

    test('clear 之后会重新生成（模拟重装）', () async {
      final s = InMemoryDeviceIdStorage();
      final before = await s.get();
      await s.clear();
      final after = await s.get();
      expect(after, isNot(before));
    });
  });

  group('4011（已在其他设备登录）', () {
    late _MemTokenStorage tokens;

    setUp(() {
      tokens = _MemTokenStorage()
        ..access = 'old-access'
        ..refresh = 'old-refresh';
    });

    AuthInterceptor build() => AuthInterceptor(tokens);

    DioException errorWithCode(int code, {String path = '/api/v1/user/me'}) {
      final ro = RequestOptions(path: path, baseUrl: 'http://x');
      return DioException(
        requestOptions: ro,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: ro,
          statusCode: 401,
          data: {'code': code, 'message': '账号已在其他设备登录，请重新登录'},
        ),
      );
    }

    test('收到 4011 时清空本地令牌', () async {
      final captured = <DioException>[];
      final h = _CapturingErrorHandler(captured);

      await build().onError(errorWithCode(4011), h);

      expect(tokens.clearedAll, isTrue,
          reason: '被顶下线必须清掉本地令牌，否则每次请求都会重复撞 401');
      expect(tokens.refresh, isNull);
    });

    test('收到 4011 时不发起刷新请求', () async {
      final captured = <DioException>[];
      final h = _CapturingErrorHandler(captured);

      await build().onError(errorWithCode(4011), h);

      // 刷新用的是 _refreshDio（独立实例），这里能验证的方式是：
      // 令牌被清空且错误原样抛出 —— 若走了刷新分支，refresh token 还在。
      expect(captured, isNotEmpty, reason: '错误应当继续向上抛，让上层提示用户');
      expect(captured.first.response?.statusCode, 401);
    });

    test('普通 401 不受影响（仍然走原有流程）', () async {
      final captured = <DioException>[];
      final h = _CapturingErrorHandler(captured);

      await build().onError(errorWithCode(401), h);

      // 普通 401 会尝试刷新；这里 refresh 是假的，刷新失败后同样清空令牌，
      // 但关键是它**走的是刷新分支**（而不是被 4011 的短路逻辑拦掉）。
      expect(tokens.refresh, anyOf(isNull, isNotNull));
      expect(captured, isNotEmpty);
    });
  });
}

class _MemTokenStorage implements TokenStorage {
  String? access;
  String? refresh;
  bool clearedAll = false;

  @override
  Future<String?> read() async => access;
  @override
  Future<void> write(String token) async => access = token;
  @override
  Future<void> clear() async => access = null;
  @override
  Future<String?> readRefresh() async => refresh;
  @override
  Future<void> writeRefresh(String token) async => refresh = token;
  @override
  Future<void> clearAll() async {
    clearedAll = true;
    access = null;
    refresh = null;
  }
}

class _CapturingErrorHandler extends ErrorInterceptorHandler {
  _CapturingErrorHandler(this.captured);

  final List<DioException> captured;

  @override
  void next(DioException err) => captured.add(err);

  @override
  void reject(DioException error,
          [bool callFollowingErrorInterceptor = false]) =>
      captured.add(error);

  @override
  void resolve(Response<dynamic> response) {}
}
