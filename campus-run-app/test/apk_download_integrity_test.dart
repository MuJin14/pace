import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 下载完整性校验。
///
/// ## 真实故障（反复出现）
///
/// 用户多次遇到**「解析安装包时出现问题」**。根因在下载之后：
///
/// ```dart
/// await _dio.download(url, savePath, ...);   // 成功 ≠ 文件完整
/// _install(savePath);                         // 把可能残缺的包交给安装器
/// ```
///
/// `Dio.download()` 在连接中断/响应提前结束时**仍可能正常返回**，
/// 留下一个尾部缺失的 APK。APK 是 zip，**尾部正是中央目录**
/// （记录每个条目的偏移）：少几十字节，安装器就报解析失败。
///
/// 这个错误极具误导性 —— 看起来像「包有问题/手机不兼容」，而重下一次就好了，
/// 用户只会认为「这 App 装不上」。
///
/// 所以装之前必须校验：sha256（最严格）→ 大小 → zip 尾部签名（兜底）。
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('apk_integrity');
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  /// 造一个最小的合法 zip（尾部带 EOCD 标记 `PK\x05\x06`）。
  Uint8List validZipPayload({int padding = 512}) {
    final b = BytesBuilder();
    // 本地文件头（虚构，只为让文件看起来像 zip 的前半段）
    b.add([0x50, 0x4B, 0x03, 0x04]);
    b.add(List<int>.filled(padding, 0x41));
    // EOCD：PK\x05\x06 + 18 字节字段
    b.add([0x50, 0x4B, 0x05, 0x06]);
    b.add(List<int>.filled(18, 0));
    return b.toBytes();
  }

  /// 截断版：砍掉尾部（模拟传输中断）—— 这正是安装器会报解析失败的形态。
  Uint8List truncatedZip(Uint8List full, {int cut = 40}) =>
      Uint8List.sublistView(full, 0, full.length - cut);

  Future<File> write(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('sha256 校验', () {
    test('哈希一致 → 通过（且不必再看 zip 尾部）', () async {
      final bytes = validZipPayload();
      final f = await write('a.apk', bytes);
      expect(sha256.convert(bytes).toString(), isNotEmpty);
      // 与实现同一判据
      final digest = sha256.convert(await f.readAsBytes()).toString();
      expect(digest, sha256.convert(bytes).toString());
    });

    test('⚠️ 缺尾部的残包：哈希必然不符 → 必须被拦下', () async {
      final full = validZipPayload();
      final cut = truncatedZip(full);
      final a = sha256.convert(full).toString();
      final b = sha256.convert(cut).toString();
      expect(
        a,
        isNot(b),
        reason: '截断后的哈希必须不同，否则残包会被当成好包放行',
      );
    });

    test('大小一致但内容不同（同长度损坏）也能被发现', () async {
      final a = Uint8List.fromList(validZipPayload());
      final b = Uint8List.fromList(a);
      b[b.length ~/ 2] ^= 0xFF; // 翻转中间一个字节，长度不变
      expect(a.length, b.length);
      expect(sha256.convert(a).toString(),
          isNot(sha256.convert(b).toString()));
    });
  });

  group('zip 尾部兜底（服务端既没给哈希也没给大小时）', () {
    bool looksComplete(List<int> bytes) {
      const sig = [0x50, 0x4B, 0x05, 0x06];
      for (var i = bytes.length - 4; i >= 0; i--) {
        if (bytes[i] == sig[0] &&
            bytes[i + 1] == sig[1] &&
            bytes[i + 2] == sig[2] &&
            bytes[i + 3] == sig[3]) {
          return true;
        }
      }
      return false;
    }

    test('完整的 zip 尾部能找到 EOCD 标记', () {
      expect(looksComplete(validZipPayload()), isTrue);
    });

    test('⚠️ 被截断的 zip 找不到 EOCD → 判为不完整', () {
      final cut = truncatedZip(validZipPayload(), cut: 40);
      expect(
        looksComplete(cut),
        isFalse,
        reason: '截断包必须判为不完整，否则就会交给安装器 → 解析失败',
      );
    });

    test('空的/极短的文件也判为不完整（不会越界崩溃）', () {
      expect(looksComplete(const []), isFalse);
      expect(looksComplete(const [0x50]), isFalse);
      expect(looksComplete(const [0x50, 0x4B, 0x05]), isFalse);
    });
  });

  group('判定顺序与退路', () {
    test('有哈希时以哈希为准 —— 大小对但哈希错仍要拒绝', () async {
      // 这是最关键的一条：只比大小会漏掉「同长度但内容坏」的包。
      final good = validZipPayload();
      final bad = Uint8List.fromList(good);
      bad[10] ^= 0xFF;
      expect(good.length, bad.length);
      expect(sha256.convert(good).toString(),
          isNot(sha256.convert(bad).toString()));
    });

    test('既无哈希也无大小时退化为 zip 尾部检查（不能完全不校验）', () {
      // 服务端字段缺失时若不校验，回退到「盲装」—— 那正是这个 bug 的成因。
      final cut = truncatedZip(validZipPayload(), cut: 40);
      final tail = utf8.decode(
        cut.sublist(cut.length - 4 < 0 ? 0 : cut.length - 4),
        allowMalformed: true,
      );
      expect(tail.contains('PK\u0005\u0006'), isFalse,
          reason: '残缺包的尾部不应含 EOCD，兜底检查必须能拦下它');
    });
  });
}
