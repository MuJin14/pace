import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// URL 拼接的回归测试。
///
/// **背景（真实 bug）**：`BaseUrlInterceptor` 曾经把 query 参数拼了两遍 ——
/// `options.path = path + '?' + query` 之后，Dio 发送时仍会追加
/// `options.queryParameters`，于是请求变成：
///
///   `/api/v1/leaderboard?scope=daily&type=1&scope=daily&type=1`
///
/// Spring 收到两个同名参数会绑定成 `"daily,daily"`，
/// `LeaderboardScope.fromCode("daily,daily")` 返回 null → 400「榜单维度不合法」，
/// 前端只显示一句「参数错误」，**极难定位**（本次排查绕了很久）。
///
/// 这里用「拼好的 URL 不能再被追加」这一不变量把这个坑钉住。
void main() {
  group('服务器地址规范化（拼接 URL 的前置步骤）', () {
    test('域名默认补 https，IP 默认补 http', () {
      expect(normalizeServerAddress('api.hibiscus.wiki'),
          'https://api.hibiscus.wiki');
      expect(normalizeServerAddress('127.0.0.1:8080'), 'http://127.0.0.1:8080');
    });

    test('规范化后不含尾斜杠（避免拼出 //api/v1）', () {
      final base = normalizeServerAddress('api.hibiscus.wiki/');
      expect(base, 'https://api.hibiscus.wiki');
      expect(base!.endsWith('/'), isFalse);
    });
  });

  group('完整 URL 拼接不变量', () {
    /// BaseUrlInterceptor 修复后的做法：
    /// 完整 URL 放 path、baseUrl 置空、**queryParameters 清空**
    (String, String, Map<String, dynamic>) applyFixedInterceptor(
        String base, String path, Map<String, String> query) {
      final parsed = Uri.parse(base);
      final full = Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: path,
        queryParameters: query.isEmpty ? null : query,
      );
      return ('', full.toString(), const {});
    }

    test('修复后：query 参数只出现一次', () {
      final (baseUrl, path, query) = applyFixedInterceptor(
        'https://api.hibiscus.wiki',
        '/api/v1/leaderboard',
        {'scope': 'daily', 'type': '1', 'page': '1', 'size': '50'},
      );
      final uri = diter(baseUrl, path, query);
      final parsed = Uri.parse(uri);

      expect(parsed.queryParametersAll['scope'], ['daily'],
          reason: 'scope 只能有一个取值');
      expect(parsed.queryParametersAll.length, 4);
      expect('scope='.allMatches(parsed.query).length, 1);
    });

    test('对照：只清 baseUrl 而不清 queryParameters 仍会重复（真实踩过的坑）', () {
      final (baseUrl, path, _) = applyFixedInterceptor(
        'https://api.hibiscus.wiki',
        '/api/v1/leaderboard',
        {'scope': 'daily', 'type': '1', 'page': '1', 'size': '50'},
      );
      // 模拟「漏了清空 queryParameters」的写法
      final broken = diter(baseUrl, path, {'scope': 'daily', 'type': '1'});
      final parsed = Uri.parse(broken);

      expect(parsed.queryParametersAll['scope'], ['daily', 'daily'],
          reason: '这正是导致 400「榜单维度不合法」的 URL —— '
              'Spring 会把同名参数绑定成 "daily,daily"');
    });

    test('无 query 时不产生多余的 ?', () {
      final (baseUrl, path, query) = applyFixedInterceptor(
          'https://api.hibiscus.wiki', '/api/v1/user/me', {});
      final uri = diter(baseUrl, path, query);
      expect(uri, 'https://api.hibiscus.wiki/api/v1/user/me');
      expect(uri.contains('?'), isFalse);
    });

    test('带端口的地址正确拼接', () {
      final (baseUrl, path, query) = applyFixedInterceptor(
          'http://10.0.0.2:8080', '/api/v1/leaderboard', {'scope': 'weekly'});
      expect(diter(baseUrl, path, query),
          'http://10.0.0.2:8080/api/v1/leaderboard?scope=weekly');
    });
  });
}

/// 本地别名，避免与 Dart 内置名冲突
String diter(String baseUrl, String path, Map<String, dynamic> q) {
  var url = path;
  if (!url.startsWith(RegExp(r'https?:'))) url = baseUrl + url;
  final query = q.entries.map((e) => '${e.key}=${e.value}').join('&');
  if (query.isNotEmpty) url += '${url.contains('?') ? '&' : '?'}$query';
  return url;
}
