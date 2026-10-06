import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 服务器地址解析与持久化的测试。
///
/// 背景：API 地址原先只能编译期注入，换一次网络就要重新构建安装。
/// 现在可在 App 内修改，所以"用户手输的字符串"必须被正确规范化 ——
/// 否则一个多余空格或漏写的 http:// 就会导致整个 App 连不上后端。
void main() {
  group('normalizeServerAddress 规范化', () {
    test('IP / 端口 自动补 http://（本地调试目标几乎都是明文）', () {
      expect(normalizeServerAddress('10.167.141.58:8080'),
          'http://10.167.141.58:8080');
      expect(normalizeServerAddress('192.168.1.5:8080'),
          'http://192.168.1.5:8080');
      expect(normalizeServerAddress('127.0.0.1:8080'),
          'http://127.0.0.1:8080');
    });

    test('域名自动补 https://（曾经一律补 http，导致 https 站点连不上）', () {
      // 这是真实踩过的缺陷：Cloudflare 边缘只接受 https，
      // 补成 http 会一直超时，用户看到「地址填对了却连不上」。
      expect(normalizeServerAddress('api.hibiscus.wiki'),
          'https://api.hibiscus.wiki');
      expect(normalizeServerAddress('api.example.com:443'),
          'https://api.example.com:443');
      expect(normalizeServerAddress('xxx.trycloudflare.com'),
          'https://xxx.trycloudflare.com');
    });

    test('localhost / 无点号主机名按 http 处理', () {
      expect(normalizeServerAddress('localhost:8080'), 'http://localhost:8080');
      expect(normalizeServerAddress('myserver:8080'), 'http://myserver:8080');
    });

    test('保留已有的 http / https（不覆盖用户显式写法）', () {
      expect(normalizeServerAddress('http://10.0.0.2:8080'),
          'http://10.0.0.2:8080');
      expect(normalizeServerAddress('https://api.example.com'),
          'https://api.example.com');
      // 显式写 http 的域名也尊重用户（比如内网自签名场景）
      expect(normalizeServerAddress('http://api.example.com'),
          'http://api.example.com');
    });

    test('去掉首尾空白（手机上粘贴地址常带空格）', () {
      expect(normalizeServerAddress('  127.0.0.1:8080  '),
          'http://127.0.0.1:8080');
      expect(normalizeServerAddress('  api.hibiscus.wiki  '),
          'https://api.hibiscus.wiki');
    });

    test('去掉结尾斜杠，避免拼出 //api/v1', () {
      expect(normalizeServerAddress('http://10.0.0.2:8080/'),
          'http://10.0.0.2:8080');
      expect(normalizeServerAddress('http://10.0.0.2:8080///'),
          'http://10.0.0.2:8080');
      expect(normalizeServerAddress('api.hibiscus.wiki/'),
          'https://api.hibiscus.wiki');
    });

    test('空白 / 空串返回 null（非法）', () {
      expect(normalizeServerAddress(''), isNull);
      expect(normalizeServerAddress('   '), isNull);
      expect(normalizeServerAddress('/'), isNull);
      expect(normalizeServerAddress('///'), isNull);
    });

    test('没有主机名的输入返回 null', () {
      expect(normalizeServerAddress('http://'), isNull);
      expect(normalizeServerAddress('https://'), isNull);
      expect(normalizeServerAddress('http'), isNull);
    });

    test('带端口与路径的地址可用', () {
      expect(normalizeServerAddress('10.0.0.2:8080/api'),
          'http://10.0.0.2:8080/api');
    });
  });

  group('ServerAddressStorage 持久化', () {
    test('写入后可读回，且自动去空白', () async {
      final s = InMemoryServerAddressStorage();
      await s.write('  http://10.0.0.2:8080  ');
      expect(await s.read(), 'http://10.0.0.2:8080');
    });

    test('clear 后读回 null（恢复默认地址）', () async {
      final s = InMemoryServerAddressStorage();
      await s.write('http://10.0.0.2:8080');
      expect(await s.read(), isNotNull);
      await s.clear();
      expect(await s.read(), isNull);
    });
  });
}
