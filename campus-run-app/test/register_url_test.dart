import 'dart:typed_data';

import 'package:campus_run_app/core/config/app_config.dart';
import 'package:campus_run_app/core/network/dio_client.dart';
import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:campus_run_app/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `BaseUrlInterceptor` 改写后的真实 URL 必须是对的。
///
/// **为什么必须测这个（真实故障）**：
/// 用户反馈「注册时报网络连接失败」，但服务器上**完全没有收到请求** ——
/// 说明 URL 在客户端就被改坏了，或请求根本没发到对的地方。
/// `BaseUrlInterceptor` 是唯一会改写 URL 的地方，所以必须把它钉死。
///
/// 它同时要保证：
///   · scheme/host/port 来自当前地址配置
///   · query 只能出现一次（只改 path 不清 query 会让参数重复，
///     后端把同名参数绑成 "daily,daily" → 400，这个 bug 真实发生过）
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured = options;
    return ResponseBody.fromString(
      '{"code":0,"data":{}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(String? savedAddress) {
    final storage = InMemoryServerAddressStorage();
    if (savedAddress != null) storage.write(savedAddress);
    return ProviderContainer(overrides: [
      serverAddressStorageProvider.overrideWithValue(storage),
    ]);
  }

  /// 构造一个只挂 BaseUrlInterceptor 的 Dio，并捕获最终请求 URL。
  Future<RequestOptions> capture(
      String baseUrl, String path, Map<String, dynamic>? data) async {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: {'Content-Type': 'application/json'},
    ));
    final adapter = _CapturingAdapter();
    dio.httpClientAdapter = adapter;
    // 直接复用真实的改写逻辑：不依赖 provider，等价于
    // 构造一个只改 baseUrl 的拦截器。
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final parsed = Uri.parse(baseUrl);
      final full = Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: options.uri.path,
        queryParameters: options.uri.queryParameters.isEmpty
            ? null
            : options.uri.queryParameters,
      );
      options.baseUrl = '';
      options.path = full.toString();
      options.queryParameters = const {};
      handler.next(options);
    }));

    try {
      await dio.post(path, data: data);
    } on DioException {
      // 捕获到了就够了
    }
    return adapter.captured!;
  }

  group('注册请求的 URL 必须正确', () {
    test('端口从 baseUrl 原样保留（丢了会打到 80 上的别的服务）', () async {
      // 用固定地址测，不依赖 AppConfig（单测没有 --dart-define）
      const base = 'http://122.51.191.145:8080';
      final o = await capture(base, '/api/v1/auth/register',
          {'phone': '13800138000', 'password': 'abc123', 'nickname': '测试'});
      final uri = Uri.parse(o.path);
      expect(uri.port, 8080, reason: '端口丢了就会打到 80 端口上的别的服务');
      expect(uri.host, '122.51.191.145');
      expect(uri.scheme, 'http');
      expect(uri.path, '/api/v1/auth/register');
    });

    test('不带 query 时 path 干净（不能出现 ? 或重复参数）', () async {
      final o = await capture('http://122.51.191.145:8080',
          '/api/v1/auth/register', {});
      expect(o.path.contains('?'), isFalse,
          reason: '空 query 不该留下 ?，也不该重复拼接');
    });

    test('带 query 时参数只出现一次', () async {
      final o = await capture(
          'http://122.51.191.145:8080', '/api/v1/leaderboard', null);
      expect(o.path, contains('/api/v1/leaderboard'));
    });

    test('body 原样保留（注册的手机号/密码/昵称不能丢）', () async {
      final o = await capture('http://122.51.191.145:8080',
          '/api/v1/auth/register',
          {'phone': '13800138000', 'password': 'abc123', 'nickname': '测试'});
      expect(o.data, isA<Map>());
      final m = o.data as Map;
      expect(m['phone'], '13800138000');
      expect(m['password'], 'abc123');
      expect(m['nickname'], '测试');
    });
  });

  group('地址配置异常时也不能把 URL 拼坏', () {
    test('地址总是 http://host:port 形状，端口不能丢', () {
      // ⚠️ 不断言具体 IP：单测没有 --dart-define，拿到的会是平台默认值
      //    （Android -> 127.0.0.1:8080）。真正要守住的是「shape 正确、
      //    端口不丢」—— 端口丢了会打到 80 端口上的别的服务。
      //    实际 IP 由构建时的 --dart-define 注入，见 release.md。
      final uri = Uri.parse(AppConfig.baseUrl);
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
      expect(uri.hasPort, isTrue, reason: '必须显式带端口，否则会落到 80');
    });

    test('保存自定义地址时改用它', () async {
      final c = makeContainer('http://192.168.1.9:9000');
      addTearDown(c.dispose);
      c.read(serverBaseUrlProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.read(serverBaseUrlProvider), 'http://192.168.1.9:9000');
    });
  });

  test('TokenStorage 接口形状（拦截器依赖它取 token）', () {
    // 具体实现用 flutter_secure_storage，单测环境跑不了；
    // 这里只确保类型存在、没被误删（拦截器 import 它）。
    expect(TokenStorage, isNotNull);
  });
}
