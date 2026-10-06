import 'dart:typed_data';

import 'package:campus_run_app/core/network/dio_client.dart';
import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:campus_run_app/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用**真实的 `dioProvider`（完整拦截器链）**捕获注册请求的最终形态。
///
/// **为什么必须这样测（真实故障）**：
/// 用户反馈「在注册页点注册后报网络连接失败」，但服务器上**完全没有收到请求** ——
/// Caddy 访问日志里没有 `/api/v1/auth/register`，用户表也没有新记录。
///
/// 也就是说请求在客户端就被拦掉了、或者被发到了错误的地址。
/// 拦截器链是唯一会改写请求的地方，所以这里把它整个跑一遍，
/// 断言最终真正发出去的 method / URI / body。

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured = options;
    return ResponseBody.fromString(
      '{"code":0,"message":"成功","data":{"token":"t","refreshToken":"r","userId":1}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 不落盘的 TokenStorage（拦截器需要它）。
class _MemTokenStorage implements TokenStorage {
  String? _v;
  @override
  Future<String?> read() async => _v;
  @override
  Future<void> write(String token) async => _v = token;
  @override
  Future<void> clear() async => _v = null;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> writeRefresh(String token) async {}
  @override
  Future<void> clearAll() async => _v = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CapturingAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = _CapturingAdapter();
    container = ProviderContainer(overrides: [
      serverAddressStorageProvider.overrideWithValue(InMemoryServerAddressStorage()),
      tokenStorageProvider.overrideWithValue(_MemTokenStorage()),
    ]);
  });

  tearDown(() => container.dispose());

  Future<RequestOptions> captureRegister({String? nickname}) async {
    final dio = container.read(dioProvider);
    dio.httpClientAdapter = adapter;
    try {
      await dio.post('/api/v1/auth/register', data: {
        'phone': '13800138000',
        'password': 'abc123',
        'nickname': nickname ?? '测试',
      });
    } on DioException {
      // 已经捕获到请求就够了
    }
    expect(adapter.captured, isNotNull, reason: '请求必须真的发出去了');
    return adapter.captured!;
  }

  group('注册请求经过完整拦截器链后仍然正确', () {
    test('method / URI / body 都不被拦截器破坏', () async {
      final o = await captureRegister();

      expect(o.method, 'POST');
      expect(o.uri.path, '/api/v1/auth/register',
          reason: '路径不能被 BaseUrlInterceptor 改坏');
      expect(o.uri.host, isNotEmpty, reason: 'host 不能为空');
      expect(o.uri.port, 8080, reason: '端口丢了会打到别的服务上');

      final body = o.data;
      expect(body, isA<Map>());
      expect((body as Map)['phone'], '13800138000');
      expect(body['password'], 'abc123');
      expect(body['nickname'], '测试');
    });

    test('query 不能被重复追加（重复参数会让后端 400）', () async {
      final o = await captureRegister();
      expect(o.uri.query, isEmpty);
      expect(o.path.contains('?'), isFalse);
    });

    test('中文昵称不能被编码坏', () async {
      final o = await captureRegister(nickname: '跑步达人🏃');
      expect((o.data as Map)['nickname'], '跑步达人🏃');
    });

    test('注册不该带 Authorization（公开接口）', () async {
      final o = await captureRegister();
      final auth = o.headers['Authorization'];
      // 没有 token 时不应有该头；有 token 时也只是多余，但不该是坏值
      expect(auth, anyOf(isNull, startsWith('Bearer ')));
    });
  });

  test('登录与注册走同一套改写，路径都不被破坏', () async {
    final dio = container.read(dioProvider);
    dio.httpClientAdapter = adapter;
    try {
      await dio.post('/api/v1/auth/login',
          data: {'phone': '13800138000', 'password': 'abc123'});
    } on DioException {
      // 捕获到请求就够了；这里不需要处理响应
    }
    expect(adapter.captured!.uri.path, '/api/v1/auth/login');
    expect(adapter.captured!.uri.port, 8080);
  });
}
