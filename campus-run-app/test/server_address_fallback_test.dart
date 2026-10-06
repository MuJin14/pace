import 'package:campus_run_app/core/config/app_config.dart';
import 'package:campus_run_app/core/network/dio_client.dart';
import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 失效服务器地址的处理。
///
/// **为什么必须有这组测试（真实事故）**：
/// 1.2.0 / 1.3.0 把编译期地址改成了 `https://api.hibiscus.wiki:8443`。
/// 后来那个域名在 Cloudflare 侧被改成「仅 DNS」，手机上连到的就是服务器
/// 裸 IP，看到的是一张 **Android 不信任的 Cloudflare 源站证书**，
/// 直接拒绝连接 → App 显示「网络问题」。
///
/// 致命之处在于：**本地保存的地址优先级高于编译期地址**。
/// 所以即使用户装了修好的新包，只要旧地址还留在 shared_preferences 里，
/// 就依然连不上 —— 现象是「更新之后还是进不去」，用户完全无法自救。
///
/// 修法两条：
///   1. 保存的地址若属于已知失效前缀 → 启动时直接丢弃并清除持久化；
///   2. 连接类失败时自动回退到编译期地址（不写入本地，尊重用户主动选择）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(ServerAddressStorage storage) {
    return ProviderContainer(
      overrides: [
        serverAddressStorageProvider.overrideWithValue(storage),
      ],
    );
  }

  group('已知失效的服务器地址会被丢弃', () {
    test('保存的是旧 HTTPS 域名 → 回落到编译期地址并清除持久化', () async {
      final storage = InMemoryServerAddressStorage();
      await storage.write('https://api.hibiscus.wiki:8443');

      final c = makeContainer(storage);
      addTearDown(c.dispose);

      // 触发 build（内部会异步加载本地覆写）
      c.read(serverBaseUrlProvider);
      // 等微任务跑完
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(serverBaseUrlProvider), AppConfig.baseUrl,
          reason: '失效地址必须被丢弃，回落到编译期地址');
      expect(await storage.read(), isNull,
          reason: '同时要清除持久化，否则下次启动还会读到它');
    });

    test('保存的是旧 HTTP 域名 → 同样丢弃', () async {
      final storage = InMemoryServerAddressStorage();
      await storage.write('http://api.hibiscus.wiki');

      final c = makeContainer(storage);
      addTearDown(c.dispose);

      c.read(serverBaseUrlProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(serverBaseUrlProvider), AppConfig.baseUrl);
      expect(await storage.read(), isNull);
    });
  });

  group('用户自己填的地址必须保留', () {
    test('局域网地址不会被误清（不能因为「非默认」就丢掉用户的选择）', () async {
      final storage = InMemoryServerAddressStorage();
      await storage.write('http://192.168.1.9:8080');

      final c = makeContainer(storage);
      addTearDown(c.dispose);

      c.read(serverBaseUrlProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(serverBaseUrlProvider), 'http://192.168.1.9:8080',
          reason: '这是用户主动指向的服务器，App 无权替他改掉');
      expect(await storage.read(), 'http://192.168.1.9:8080');
    });

    test('自定义域名不会被误清', () async {
      final storage = InMemoryServerAddressStorage();
      await storage.write('https://myserver.example.com');

      final c = makeContainer(storage);
      addTearDown(c.dispose);

      c.read(serverBaseUrlProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(serverBaseUrlProvider), 'https://myserver.example.com');
    });

    test('其它 hibiscus 子域不受影响（只有确认失效的那几个才清）', () async {
      final storage = InMemoryServerAddressStorage();
      // dl 子域是下载域，不是 API 地址；前缀匹配必须精确到 api.
      await storage.write('https://dl.hibiscus.wiki:8443');

      final c = makeContainer(storage);
      addTearDown(c.dispose);

      c.read(serverBaseUrlProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(serverBaseUrlProvider), 'https://dl.hibiscus.wiki:8443',
          reason: '只清 api.hibiscus.wiki，不要误伤同域名的其它主机');
    });
  });

  test('没有保存地址时保持编译期地址', () async {
    final storage = InMemoryServerAddressStorage();

    final c = makeContainer(storage);
    addTearDown(c.dispose);

    c.read(serverBaseUrlProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(serverBaseUrlProvider), AppConfig.baseUrl);
  });
}
