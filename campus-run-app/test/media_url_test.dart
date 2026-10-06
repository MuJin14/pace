import 'package:campus_run_app/core/network/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// 媒体地址改写。
///
/// **为什么必须有（真实事故）**：
/// 服务端返回的头像/聊天图是**绝对地址**，域名由后端 `PUBLIC_BASE_URL` 拼接，
/// 于是数据库里存的是 `https://api.hibiscus.wiki:8443/uploads/...`。
///
/// 那个域名一旦对客户端不可达（证书不被 Android 信任、DNS 被改、域名到期），
/// **所有图片都加载不出来** —— 而 App 本身其实连得上服务器，
/// 表现为「能登录、能聊天，但头像和图片全是空白」。
///
/// 修法：加载前统一换成当前连接地址，只保留路径。
void main() {
  group('绝对地址改写成当前服务器', () {
    test('换成当前 baseUrl 的 scheme/host/port，路径保留', () {
      expect(
        resolveMediaUrlWithBase(
            'http://122.51.191.145:8080', 'https://api.hibiscus.wiki:8443/uploads/avatar/a.jpg'),
        'http://122.51.191.145:8080/uploads/avatar/a.jpg',
      );
    });

    test('域名换了但路径不变', () {
      expect(
        resolveMediaUrlWithBase('http://10.0.0.5:8080', 'https://old.example.com/uploads/chat/b.png'),
        'http://10.0.0.5:8080/uploads/chat/b.png',
      );
    });

    test('query 参数要保留（图片可能带签名/尺寸参数）', () {
      expect(
        resolveMediaUrlWithBase('http://1.2.3.4:8080', 'https://x.com/uploads/a.jpg?w=100&h=200'),
        'http://1.2.3.4:8080/uploads/a.jpg?w=100&h=200',
      );
    });

    test('baseUrl 带 https 时结果也是 https', () {
      expect(
        resolveMediaUrlWithBase('https://api.example.com', 'http://old.com/uploads/a.jpg'),
        'https://api.example.com/uploads/a.jpg',
      );
    });
  });

  group('相对路径直接补 baseUrl', () {
    test('/ 开头', () {
      expect(
        resolveMediaUrlWithBase('http://122.51.191.145:8080', '/uploads/avatar/a.jpg'),
        'http://122.51.191.145:8080/uploads/avatar/a.jpg',
      );
    });
  });

  group('不该动的要保持原样', () {
    test('data: 内联资源', () {
      const u = 'data:image/png;base64,iVBORw0KGgo=';
      expect(resolveMediaUrlWithBase('http://1.2.3.4:8080', u), u);
    });

    test('asset: 表情包（本地资源，跟服务器无关）', () {
      const u = 'asset:stickers/happy.png';
      expect(resolveMediaUrlWithBase('http://1.2.3.4:8080', u), u);
    });

    test('普通相对文件名不猜（可能本就是本地资源）', () {
      expect(resolveMediaUrlWithBase('http://1.2.3.4:8080', 'happy.png'), 'happy.png');
    });
  });

  group('空值与异常输入', () {
    test('null 与空串返回 null', () {
      expect(resolveMediaUrlWithBase('http://1.2.3.4:8080', null), isNull);
      expect(resolveMediaUrlWithBase('http://1.2.3.4:8080', ''), isNull);
      expect(resolveMediaUrlWithBase('http://1.2.3.4:8080', '   '), isNull);
    });

    test('baseUrl 非法时不抛异常（宁可原样返回也不要崩）', () {
      // 不能因为地址没配置好就让整个列表崩掉
      expect(() => resolveMediaUrlWithBase('', '/uploads/a.jpg'), returnsNormally);
      expect(() => resolveMediaUrlWithBase('not a url', '/uploads/a.jpg'), returnsNormally);
    });

    test('无法解析的绝对地址原样返回', () {
      const u = 'https://';
      expect(() => resolveMediaUrlWithBase('http://1.2.3.4:8080', u), returnsNormally);
    });
  });

  test('默认地址是 http://host:port 形状（不依赖域名与 Cloudflare）', () {
    // 不断言具体 IP：单测没有 --dart-define，拿到的是平台默认值。
    // 要守住的是「必须显式带端口」—— 丢了端口会落到 80 上的别的服务。
    final uri = Uri.parse(fallbackBaseUrl);
    expect(uri.scheme, anyOf('http', 'https'));
    expect(uri.hasPort, isTrue);
    // 关键：默认地址不应该是需要 DNS + 证书的 https 域名
    expect(fallbackBaseUrl, isNot(contains('hibiscus')));
  });
}
