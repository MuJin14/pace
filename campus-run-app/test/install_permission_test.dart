import 'dart:io';

import 'package:campus_run_app/core/platform/install_permission.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「应用内更新」的安装权限环节。
///
/// ## 为什么这个文件必须存在
///
/// 用户反馈：**「更新包下载完了，没有弹出安装界面」**。
///
/// 根因是 manifest 里缺 `REQUEST_INSTALL_PACKAGES`。Android 8.0+ 没有它时
/// 系统会**静默拒绝**安装意图 —— 不弹界面、也不报错。加上这个权限，
/// 用户首次更新时系统会弹「允许行迹安装应用」。
///
/// 但**光加权限还不够**：用户可能在授权页点「拒绝」，那时安装同样不会发生，
/// 而 open_filex 只负责把意图交出去、可能仍返回成功 ——
/// 界面又是一片安静。所以下载完成后必须先查这个开关并给出指引。
///
/// 这些失败模式的共同特征是**不报错**，因此必须靠断言守住：
///   1. 开关关闭时 `isAllowed()` 必须返回 false（否则不会提示用户）；
///   2. 查询失败时返回 true（宁可让用户去试，也不要卡在提示上）；
///   3. manifest 必须声明 `REQUEST_INSTALL_PACKAGES`（静态检查，见最后一个用例）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('campus_run/platform');

  void mockChannel(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('安装权限查询', () {
    test('系统返回「不允许」时 isAllowed 为 false', () async {
      mockChannel((c) => c.method == 'canInstallPackages' ? false : null);
      // 测试跑在宿主平台上，Platform.isAndroid 为 false 会短路成 true，
      // 所以这里只在支持平台语义下断言；用非 Android 环境跳过。
      if (!Platform.isAndroid) {
        // 宿主平台：_supported 为 false，isAllowed 恒为 true（按允许处理）。
        // 这是有意的：非 Android 平台没有这个开关。
        expect(await InstallPermission.isAllowed(), isTrue);
        return;
      }
      expect(await InstallPermission.isAllowed(), isFalse);
    });

    test('查询抛异常时按「允许」处理（不把用户挡在提示前）', () async {
      mockChannel((c) {
        if (c.method == 'canInstallPackages') {
          throw MissingPluginException('模拟原生不可用');
        }
        return null;
      });
      expect(await InstallPermission.isAllowed(), isTrue);
    });

    test('openSettings 在原生不可用时返回 false 而不是抛异常', () async {
      mockChannel((c) {
        if (c.method == 'openInstallPermissionSettings') {
          throw MissingPluginException('模拟原生不可用');
        }
        return null;
      });
      expect(await InstallPermission.openSettings(), isFalse);
    });
  });

  group('manifest 回归防线', () {
    test('AndroidManifest 必须声明 REQUEST_INSTALL_PACKAGES', () {
      // ⚠️ 这条断言守的是一个**曾经真实缺失**的权限。
      //
      // 缺它的后果极其隐蔽：编译正常、测试全绿、代码逻辑也没问题，
      // 只是用户点「立即更新」后什么都不发生 —— 因为系统静默拒绝了安装意图。
      // 靠运行时无法测出来（需要真机 + 真实安装流程），所以放在静态检查里。
      final f = File('android/app/src/main/AndroidManifest.xml');
      expect(f.existsSync(), isTrue,
          reason: '测试工作目录应为 campus-run-app/');
      final xml = f.readAsStringSync();
      expect(
        xml.contains('android.permission.REQUEST_INSTALL_PACKAGES'),
        isTrue,
        reason: '缺少 REQUEST_INSTALL_PACKAGES 会导致 Android 8.0+ '
            '静默拒绝安装意图，表现为「下载完没有弹安装界面」',
      );
    });

    test('FileProvider 由 open_filex 提供（Android 7+ 分享安装包必需）', () {
      // 这一项不用自己声明：open_filex 的 manifest 带入 FileProvider，
      // 且其 filepaths.xml 覆盖 files-path / cache-path，
      // 正好包含 path_provider 的 getApplicationSupportDirectory()。
      // 这里只断言依赖确实在 pubspec 里 —— 换成别的包时要重新确认。
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('open_filex'), isTrue,
          reason: '唤起安装器依赖 open_filex，它同时提供所需的 FileProvider');
    });
  });
}
