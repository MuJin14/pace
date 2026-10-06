import 'package:campus_run_app/app.dart';
import 'package:campus_run_app/core/platform/app_version.dart';
import 'package:campus_run_app/core/update/pending_update_provider.dart';
import 'package:campus_run_app/core/network/dio_client.dart';
import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:campus_run_app/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「检查更新」必须在**未登录时也会发生**。
///
/// **真实故障**：用户反馈「到了新版本没有自动更新，之前也没有」。
///
/// 根因是检查被放在 `MainShell` 里，而 MainShell 挂在登录后的
/// `StatefulShellRoute` 上：
///
///     启动 → 未登录 → 登录页 → 登录成功 → 主界面 → 才会检查更新
///
/// 没登录就永远不知道有新版本。而版本接口本身是**公开的**
/// （不带 token 也返回 200），根本不需要登录态。
///
/// ⚠️ 这条链路特别难发现，因为每一层都是「静默失败」：
///   · 检查更新失败被 catch 掉，只写 debugPrint；
///   · 没登录时压根没有请求发出去，日志里也看不出异常。
/// 只能靠测试断言「请求确实发出去了」。

/// 捕获从 `dioProvider`（含完整拦截器链）真正发出去的请求。
class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> captured = [];

  /// 版本接口的响应体。用例可以覆盖它来模拟「强制更新」等情形。
  String versionJson =
      // 服务端发布了比本机更新的版本，且 APK 已就绪
      '{"code":0,"message":"成功","data":{"latest":"9.9.9",'
      '"minSupported":"","changelog":"测试","apkReady":true,'
      '"apkUrl":"http://example.com/a.apk","apkSizeBytes":1048576}}';

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured.add(options);
    return ResponseBody.fromString(
      versionJson,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemTokenStorage implements TokenStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String token) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> writeRefresh(String token) async {}
  @override
  Future<void> clearAll() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CapturingAdapter adapter;
  late ProviderContainer container;

  /// mock 原生版本号桥。
  ///
  /// ⚠️ 为什么必须 mock：`_checkForUpdate` 外层是 catch-all，读版本失败会被
  /// **静默吞掉**，版本请求根本发不出去，测试就成了「假通过」。
  ///
  /// 这条注释原本就在（当时 mock 的是 package_info_plus）—— 而线上正是
  /// 栽在这里：插件没被注册进 Android 构建，`PackageInfo.fromPlatform()`
  /// 每次都抛异常，被同样吞掉，于是**更新弹窗从未出现过、日志里一个字都没有**，
  /// 而测试全绿。现在改用自建的原生桥（见 AppVersion），channel 也跟着换了。
  ///
  /// 另外必须重置 [AppVersion] 的静态缓存：Dart 静态字段在同一测试进程内
  /// 跨用例保留，不重置的话第二个用例会拿到上一个用例的版本号，
  /// 出现**依赖执行顺序**的假通过。
  void mockAppVersion({String version = '1.0.0'}) {
    // 测试跑在宿主平台上，Platform.isAndroid 恒为 false，会把 read()
    // 短路成空串、根本不碰 channel —— 于是整条「有更新」链路走不通，
    // 用例测的是空实现。必须显式打开。
    AppVersion.debugForceSupported = true;
    AppVersion.resetCacheForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('campus_run/platform'),
      (call) async => call.method == 'appVersion' ? version : null,
    );
  }

  setUp(() {
    adapter = _CapturingAdapter();
    container = ProviderContainer(overrides: [
      serverAddressStorageProvider
          .overrideWithValue(InMemoryServerAddressStorage()),
      tokenStorageProvider.overrideWithValue(_MemTokenStorage()),
    ]);
    // 用真实 dioProvider（完整拦截器链），只替换底层 adapter，
    // 这样「请求最终长什么样」与线上一致。
    container.read(dioProvider).httpClientAdapter = adapter;
    mockAppVersion();
  });

  tearDown(() => container.dispose());

  Iterable<RequestOptions> versionRequests() =>
      adapter.captured.where((r) => r.path.contains('/api/v1/app/version'));

  testWidgets('未登录（停在启动页/登录页）也会请求版本接口', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );
    // 首帧 + post-frame 回调 + 异步网络
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      versionRequests(),
      isNotEmpty,
      reason: '未登录时也必须检查更新 —— 检查曾经被放在登录后的 MainShell 里，'
          '导致「没登录就永远不提示新版本」',
    );
  });

  testWidgets('发出的确实是 GET /api/v1/app/version', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    final reqs = versionRequests().toList();
    expect(reqs, isNotEmpty);
    expect(reqs.first.method.toUpperCase(), 'GET');
  });

  testWidgets('检查更新只发一次请求（不随重建重复请求）', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // 触发若干次重建
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      versionRequests().length,
      1,
      reason: '一次进程只该查一次，否则更新弹窗会反复出现',
    );
  });

  testWidgets('有新版本时不直接弹窗，而是放进通知提醒（不打扰用户）', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // ⚠️ 这条断言在早期是**反过来的**（要求启动即弹「更新内容」）。
    //
    // 改成通知入口的理由（用户反馈 + 产品判断）：
    //   · 冷启动弹「要更新吗」很打扰，而用户此刻往往只想看一眼步数；
    //   · 更容易被条件反射地点「稍后」，之后再也没有入口 ——
    //     更新提示反而彻底失效。
    //
    // 现在入口常驻在右上角铃铛里，点进去才弹。
    expect(
      find.text('更新内容'),
      findsNothing,
      reason: '普通更新不该在启动时弹窗打断用户',
    );

    // 但这件事必须被**记录下来**，否则通知里就没有这一条。
    final pending = container.read(pendingUpdateProvider);
    expect(pending, isNotNull, reason: '发现新版本必须记录，否则通知入口是空的');
    expect(pending!.latest, '9.9.9');
    expect(pending.mandatory, isFalse, reason: '服务端没设强制下限，默认非强制');
  });

  testWidgets('服务端要求强制更新时仍然立即弹窗（这条不能等用户发现）', (tester) async {
    // 让版本接口下发一个 minSupported 高于本机版本的响应
    adapter.versionJson = '''
{"code":0,"message":"成功","data":{"latest":"9.9.9","minSupported":"9.0.0",
"changelog":"必须更新","apkReady":true,
"apkUrl":"http://x/app.apk","apkSizeBytes":1}}''';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('更新内容'),
      findsWidgets,
      reason: '低于 minSupported 时继续用旧版本会出问题，必须立即告知',
    );
  });
}
