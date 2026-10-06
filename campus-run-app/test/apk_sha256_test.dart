import 'package:campus_run_app/data/repositories/app_version_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `apkSha256` 字段的解析。
///
/// ## 为什么要它
///
/// 用户反馈：**「同意安装授权后点重试，又给我下载一遍」**。
///
/// 修法是下载前校验本地已存在的安装包是不是**就是这一版**，是就直接装。
/// 校验依赖服务端下发的 `apkSha256`；这个字段解析错了会有两种后果：
///
///   · 解析成 null → 退化成比大小，校验变弱（仍能用，但不是最优）；
///   · 解析出**错的**值 → 每次校验都不通过 → 用户每次都被重下 54MB，
///     也就是这个 bug 原样复现。
///
/// 所以大小写与空白必须规整一致 —— 服务端给大写十六进制、
/// 客户端算出小写，直接比较就会永远不相等。这类「差一个大小写」
/// 的坑不会报错，只会让功能静默失效。
void main() {
  AppVersionInfo parse(Map<String, dynamic> extra) => AppVersionInfo.fromJson({
        'latest': '2.0.0',
        'minSupported': '',
        'changelog': '',
        'apkReady': true,
        'apkUrl': 'http://example.com/a.apk',
        'apkSizeBytes': 1000,
        ...extra,
      });

  group('apkSha256 解析', () {
    test('正常读取', () {
      final info = parse({'apkSha256': 'abc123def456'});
      expect(info.apkSha256, 'abc123def456');
    });

    test('统一转成小写（否则与服务端算出的哈希永远不相等）', () {
      final info = parse({'apkSha256': 'ABC123DEF456'});
      expect(info.apkSha256, 'abc123def456',
          reason: '大小写不一致会让校验永远失败，用户每次都被重下');
    });

    test('去掉首尾空白', () {
      final info = parse({'apkSha256': '  abc123  '});
      expect(info.apkSha256, 'abc123');
    });

    test('没有该字段时为 null（退化为按大小校验）', () {
      expect(parse({}).apkSha256, isNull);
    });

    test('空串规整为 null，而不是留一个空校验值', () {
      // 空串如果被当成「有校验值」，下面的逻辑会拿它去比，
      // 结果永远不相等 —— 又变成每次都重下。
      expect(parse({'apkSha256': ''}).apkSha256, isNull);
      expect(parse({'apkSha256': '   '}).apkSha256, isNull);
    });
  });

  group('体积文案仍然正常（改动未影响既有行为）', () {
    test('有体积时显示 MB', () {
      expect(parse({}).sizeLabel, isNotEmpty);
    });
  });
}
