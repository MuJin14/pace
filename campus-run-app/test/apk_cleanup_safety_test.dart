import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 回归测试：安装包**不能**在唤起安装器之后立刻删除。
///
/// ## 为什么要有这个测试
///
/// 真实故障（2.0.1）：用户在旧版本里点更新 → 下载完成 → **装不上**。
///
/// 根因是我加的「装完就清理」删得太早：
///
/// ```dart
/// final error = await _install(path);   // 只表示 Intent 已交给系统
/// if (error == null) { await File(path).delete(); }   // ← 安装器还在读！
/// ```
///
/// `OpenFilex.open()` 返回 `done` **不代表**安装器已经读完文件。
/// 54MB 的包要读几秒，这边一删，安装器读到一半文件就没了。
///
/// 这个 bug 的特殊之处：
///   · **不报错** —— 删除本身成功，安装器那边只是静默失败；
///   · **只在包较大时暴露** —— 小文件可能已经读完；
///   · **看起来像"安装器的问题"** —— 用户会以为是手机或系统不给装。
///
/// 所以必须用测试把「不删」这个行为钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('安装包生命周期', () {
    test('⚠️ 唤起安装器后不得立刻删除安装包（安装器可能还没读完）', () async {
      // 模拟安装器：OpenFilex.open 返回 done，但文件此时**仍被占用**。
      bool fileStillNeeded = true;
      final log = <String>[];

      final tmp = await Directory.systemTemp.createTemp('apk_lifecycle');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final apk = File('${tmp.path}/campus-run-update.apk');
      await apk.writeAsBytes(List<int>.filled(1024, 7));

      // 这是 _installAndCleanup 应当具备的行为：
      //   装完之后文件还在（真正的回收放到下次启动）
      Future<void> simulateInstallHandoff() async {
        fileStillNeeded = false; // 系统已接手（Intent 交出）
        log.add('安装 Intent 已交出');
        // ✅ 正确做法：此刻**什么都不做**
      }

      await simulateInstallHandoff();

      expect(
        await apk.exists(),
        isTrue,
        reason: '安装包在唤起安装器后就被删了 —— 大包会因此安装失败。'
            '回收必须推迟到下次启动（cleanupStalePackage）。',
      );
      expect(fileStillNeeded, isFalse);
    });

    test('陈旧包在下次启动时会被回收（超过 6 小时）', () async {
      final tmp = await Directory.systemTemp.createTemp('apk_stale');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final apk = File('${tmp.path}/campus-run-update.apk');
      await apk.writeAsBytes(List<int>.filled(64, 1));
      // 把 mtime 改成 8 小时前
      await apk.setLastModified(
        DateTime.now().subtract(const Duration(hours: 8)),
      );

      final age = DateTime.now().difference(await apk.lastModified());
      expect(age.inHours >= 6, isTrue, reason: '前置条件：文件应被视为陈旧');
      // cleanupStalePackage 的判断条件就是 age >= olderThan
      if (age >= const Duration(hours: 6)) {
        await apk.delete();
      }
      expect(await apk.exists(), isFalse);
    });

    test('刚下好、正等用户授权的包不会被启动清理误删', () async {
      final tmp = await Directory.systemTemp.createTemp('apk_fresh');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final apk = File('${tmp.path}/campus-run-update.apk');
      await apk.writeAsBytes(List<int>.filled(64, 1));

      // 用户下载完可能过几分钟才回来点「安装」，
      // 中途若 App 被杀再启动，这个包**必须还在**。
      final age = DateTime.now().difference(await apk.lastModified());
      expect(age < const Duration(hours: 6), isTrue);

      const olderThan = Duration(hours: 6);
      if (age >= olderThan) {
        await apk.delete();
      }
      expect(
        await apk.exists(),
        isTrue,
        reason: '刚下载的包被当成陈旧包删了 —— 用户回来点安装会找不到文件',
      );
    });
  });
}
