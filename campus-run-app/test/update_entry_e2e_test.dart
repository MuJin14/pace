import 'package:campus_run_app/app.dart';
import 'package:campus_run_app/core/platform/app_version.dart';
import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:campus_run_app/core/storage/token_storage.dart';
import 'package:campus_run_app/core/network/dio_client.dart';
import 'package:campus_run_app/core/update/pending_update_provider.dart';
import 'package:campus_run_app/data/repositories/app_version_repository.dart';
import 'package:campus_run_app/features/notifications/providers/notifications_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **端到端**验证「新版本提醒出现在通知里」这条链路。
///
/// 与 `update_notification_test.dart` 的区别：那一组直接往
/// `pendingUpdateProvider` 里塞数据，测的是「塞进去之后能正确展示」；
/// 这一组**从启动开始**，走真实的检查流程，验证「它真的会被塞进去」。
///
/// ## 为什么必须分开测
///
/// 这两件事的失败模式完全不同：
///   · 塞进去但不展示  → 通知页的渲染/聚合写错了；
///   · 根本不会塞进去  → 启动检查没跑、版本号读不到、或判定条件写反了。
///
/// 第二种**在界面上看不出任何异常**（通知列表就是空的，跟没有新版本一模一样），
/// 所以必须单独守住。历史上「更新弹窗从不出现」就是第二种。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 捕获真实 dioProvider 发出的请求，并返回「有新版本」的响应。
  late _StubAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = _StubAdapter();
    container = ProviderContainer(overrides: [
      serverAddressStorageProvider
          .overrideWithValue(InMemoryServerAddressStorage()),
      tokenStorageProvider.overrideWithValue(_MemTokenStorage()),
    ]);
    container.read(dioProvider).httpClientAdapter = adapter;

    // 本机版本 1.0.0；同时打开平台开关，否则 read() 会被短路。
    AppVersion.debugForceSupported = true;
    AppVersion.resetCacheForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('campus_run/platform'),
      (call) async => call.method == 'appVersion' ? '1.0.0+1' : null,
    );
  });

  tearDown(() {
    AppVersion.debugForceSupported = null;
    AppVersion.resetCacheForTest();
    container.dispose();
  });

  testWidgets('启动后：通知聚合里出现「发现新版本」，铃铛随之亮起', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    // 首帧 -> post-frame 回调 -> 异步网络
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // ① 检查确实发出去了
    expect(
      adapter.captured.where((r) => r.path.contains('/api/v1/app/version')),
      isNotEmpty,
      reason: '启动就该请求版本接口',
    );

    // ② 通知聚合里出现更新条目
    final items = container.read(notificationsProvider);
    final updates =
        items.where((n) => n.type == AppNotificationType.appUpdate).toList();
    expect(updates, isNotEmpty,
        reason: '有新版本但通知里没有这一条 —— 用户就看不到任何入口');
    expect(updates.first.title, contains('9.9.9'));

    // ③ 铃铛红点亮起
    expect(container.read(hasNotificationsProvider), isTrue,
        reason: '铃铛必须有红点，否则用户不会点进通知页');

    // ④ 更新条目排在最前
    expect(items.first.type, AppNotificationType.appUpdate);
  });

  testWidgets('⚠️ 装上新版本后，旧的更新提醒必须被清掉（用户反馈「提示还在」）',
      (tester) async {
    // 场景还原：
    //   1. 用户被告知有新版本 → pendingUpdateProvider 里记下一条；
    //   2. 用户装完新版本切回 App —— **安装过程不会杀掉进程**，
    //      所以内存里那条记录还在，通知里照旧显示「发现新版本」；
    //   3. 回到前台应当重查一次，发现已是最新版 → 清除那条记录。
    //
    // 原来的代码在「没有新版本」时**直接 return**，从不清除 ——
    // 而且全项目没有任何地方调用过 pendingUpdateProvider.clear()。
    final c = ProviderContainer(overrides: [
      serverAddressStorageProvider
          .overrideWithValue(InMemoryServerAddressStorage()),
      tokenStorageProvider.overrideWithValue(_MemTokenStorage()),
    ]);
    addTearDown(c.dispose);
    c.read(dioProvider).httpClientAdapter = adapter;

    // 先手工制造「有一条待更新」的状态（等价于上一轮检查的结果）
    c.read(pendingUpdateProvider.notifier).found(
      AppVersionInfo(
        latest: '9.9.9',
        minSupported: '',
        changelog: '',
        apkReady: true,
        apkUrl: 'http://x/a.apk',
        apkSizeBytes: 1,
      ),
      mandatory: false,
    );
    expect(c.read(pendingUpdateProvider), isNotNull);

    // 现在服务端说「已是最新版」
    adapter.versionJson = '{"code":0,"message":"成功","data":{"latest":"1.0.0",'
        '"minSupported":"","changelog":"","apkReady":true,'
        '"apkUrl":"http://x/a.apk","apkSizeBytes":1}}';

    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const App()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      c.read(pendingUpdateProvider),
      isNull,
      reason: '已是最新版却还留着「发现新版本」——用户会一直看到这条提示',
    );
  });

  testWidgets('已经是最新版时不出现更新条目（与「没有新版本」表现一致是预期的）',
      (tester) async {
    adapter.versionJson = '{"code":0,"message":"成功","data":{"latest":"1.0.0",'
        '"minSupported":"","changelog":"","apkReady":true,'
        '"apkUrl":"http://x/a.apk","apkSizeBytes":1}}';

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final updates = container
        .read(notificationsProvider)
        .where((n) => n.type == AppNotificationType.appUpdate);
    expect(updates, isEmpty);
  });

  testWidgets('⚠️ 读不到本机版本号时**不会**误报更新（也不能判定为强制）',
      (tester) async {
    // 模拟 1.9.3 之前那个 bug 的形态：读版本失败。
    //
    // ⚠️ 顺序很关键：必须**先**把平台开关关掉、并在同一个同步块里注册会抛异常的
    // handler、清缓存。否则顺序一乱（比如先清缓存、后注册 handler），
    // 第一次 read() 就可能在 handler 生效前把值缓存下来，用例便测不到目标分支。
    AppVersion.debugForceSupported = true;
    AppVersion.resetCacheForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('campus_run/platform'),
      (call) async {
        if (call.method == 'appVersion') {
          throw MissingPluginException('模拟插件缺失');
        }
        return null;
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    // 读不到版本 -> AppVersion.read() 返回空串 -> 更新检查放弃 -> 没有任何提示。
    // 这是**有意的保守行为**：宁可漏报，不可误报「有新版本」。
    expect(
      container
          .read(notificationsProvider)
          .where((n) => n.type == AppNotificationType.appUpdate),
      isEmpty,
      reason: '读不到版本号时必须静默放弃，不能猜一个版本去比较',
    );
  });
}

/// 固定返回「有新版本」，并记录请求。
class _StubAdapter implements HttpClientAdapter {
  final List<RequestOptions> captured = [];

  String versionJson =
      '{"code":0,"message":"成功","data":{"latest":"9.9.9","minSupported":"",'
      '"changelog":"测试","apkReady":true,'
      '"apkUrl":"http://example.com/a.apk","apkSizeBytes":1048576}}';

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured.add(options);
    if (options.path.contains('/api/v1/app/version')) {
      return ResponseBody.fromString(
        versionJson,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // 其他接口返回空成功，避免干扰
    return ResponseBody.fromString(
      '{"code":0,"message":"成功","data":null}',
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
