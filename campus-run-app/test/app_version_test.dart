import 'package:campus_run_app/data/repositories/app_version_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 语义化版本比较。
///
/// **为什么值得单独测**：这段逻辑错了会导致「永远提示更新」或「永远不提示」，
/// 两种都很难在真机上第一时间发现（要发两个版本才能验证一次）。
/// 而它对纯字符串做数字切分，边界情况很多。
void main() {
  group('isVersionNewer 基本比较', () {
    test('主版本更高 → true', () {
      expect(isVersionNewer('2.0.0', '1.0.0'), isTrue);
    });

    test('次版本更高 → true', () {
      expect(isVersionNewer('1.2.0', '1.1.0'), isTrue);
    });

    test('补丁版本更高 → true', () {
      expect(isVersionNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('相同 → false', () {
      expect(isVersionNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('更低 → false', () {
      expect(isVersionNewer('1.0.0', '1.1.0'), isFalse);
      expect(isVersionNewer('1.0.0', '2.0.0'), isFalse);
    });
  });

  group('isVersionNewer 边界情况', () {
    test('段数不同：1.1 与 1.1.0 视为相同', () {
      expect(isVersionNewer('1.1', '1.1.0'), isFalse);
      expect(isVersionNewer('1.1.0', '1.1'), isFalse);
    });

    test('段数不同但确实更新：1.1.1 > 1.1', () {
      expect(isVersionNewer('1.1.1', '1.1'), isTrue);
    });

    test('多位数字按数值而非字典序比较', () {
      // 字典序会把 "10" 判成小于 "9"，这是最容易踩的坑
      expect(isVersionNewer('1.10.0', '1.9.0'), isTrue);
      expect(isVersionNewer('1.9.0', '1.10.0'), isFalse);
    });

    test('带 build 后缀（1.0.0+3）不崩，且按主版本比较', () {
      expect(isVersionNewer('1.0.0+3', '1.0.0'), isFalse);
      expect(isVersionNewer('1.1.0+1', '1.0.0+9'), isTrue);
    });

    test('空串当 0 处理，不会崩', () {
      expect(isVersionNewer('1.0.0', ''), isTrue);
      expect(isVersionNewer('', '1.0.0'), isFalse);
      expect(isVersionNewer('', ''), isFalse);
    });

    test('含非数字段时当 0 处理', () {
      expect(isVersionNewer('abc', '1.0.0'), isFalse);
      expect(isVersionNewer('2.beta', '1.0.0'), isTrue);
    });

    test('前后空格被忽略', () {
      expect(isVersionNewer(' 2.0.0 ', '1.0.0'), isTrue);
    });
  });

  group('AppVersionInfo.hasDownloadableUpdate', () {
    AppVersionInfo make({
      String latest = '1.1.0',
      bool apkReady = true,
      String? apkUrl = 'http://x/api/v1/app/download',
    }) =>
        AppVersionInfo(
          latest: latest,
          minSupported: '',
          changelog: '',
          apkReady: apkReady,
          apkUrl: apkUrl,
          apkSizeBytes: 55 * 1024 * 1024,
        );

    test('版本号与 APK 都就绪 → 可更新', () {
      expect(make().hasDownloadableUpdate, isTrue);
    });

    test('服务端没发布版本（latest 为空）→ 不提示', () {
      expect(make(latest: '').hasDownloadableUpdate, isFalse,
          reason: 'latest 为空表示「没有新版本」，客户端应直接跳过');
    });

    test('版本号有了但 APK 还没放好 → 不提示', () {
      // 否则用户点了下载会拿到 404，体验比不提示更糟
      expect(make(apkReady: false).hasDownloadableUpdate, isFalse);
    });

    test('缺下载地址 → 不提示', () {
      expect(make(apkUrl: null).hasDownloadableUpdate, isFalse);
    });

    test('体积文案可读', () {
      expect(make().sizeLabel, '55.0 MB');
    });

    test('体积未知时不显示 NaN 或 0 MB', () {
      const info = AppVersionInfo(
        latest: '1.1.0',
        minSupported: '',
        changelog: '',
        apkReady: true,
        apkUrl: 'http://x',
        apkSizeBytes: null,
      );
      expect(info.sizeLabel, '未知大小');
    });
  });
}
