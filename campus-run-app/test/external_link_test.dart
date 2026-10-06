import 'package:campus_run_app/core/platform/external_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ExternalLink` 与仓库地址的测试。
///
/// 重点不是「能打开浏览器」（那要真机才知道），而是：
///   · 通道参数是否传对（原生侧靠 `url` 这个 key 取值）；
///   · **失败时必须返回 false**，让调用方给出提示 ——
///     静默失败正是本项目历史上最难查的那类 bug；
///   · 非 Android / 非 http(s) 时不越权去调原生。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('campus_run/platform');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    ExternalLink.debugForceSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'openUrl':
          final url = (call.arguments as Map)['url'] as String?;
          return url == 'https://ok.example' ;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    ExternalLink.debugForceSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ExternalLink', () {
    test('成功打开时返回 true，并把 url 通过通道传出去', () async {
      final ok = await ExternalLink.open('https://ok.example');
      expect(ok, isTrue);
      expect(calls.length, 1);
      expect(calls.single.method, 'openUrl');
      expect((calls.single.arguments as Map)['url'], 'https://ok.example');
    });

    test('原生返回 false 时如实返回 false（调用方要给提示）', () async {
      final ok = await ExternalLink.open('https://fail.example');
      expect(
        ok,
        isFalse,
        reason: '返回 true 会让调用方以为已经打开，用户端表现为「点了没反应」',
      );
    });

    test('空地址不去打扰原生', () async {
      final ok = await ExternalLink.open('');
      expect(ok, isFalse);
      expect(calls, isEmpty);
    });

    test('非 Android 平台时直接返回 false，不调用原生', () async {
      ExternalLink.debugForceSupported = false;
      final ok = await ExternalLink.open('https://ok.example');
      expect(ok, isFalse);
      expect(calls, isEmpty);
    });

    test('⚠️ 原生通道缺失（插件/通道未注册）时返回 false 而不是抛异常', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('no implementation');
      });
      // 关键：不能把异常抛给调用方 —— 点击处若没接住，
      // 用户看到的就是一次无痕失败，而且日志里只有 Flutter 的框架报错。
      final ok = await ExternalLink.open('https://ok.example');
      expect(ok, isFalse);
    });

    test('原生抛任意异常时也返回 false（例如没有浏览器）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ActivityNotFound');
      });
      final ok = await ExternalLink.open('https://ok.example');
      expect(ok, isFalse);
    });
  });

  group('ProjectLinks', () {
    test('仓库地址是合法的 GitHub https 链接', () {
      expect(ProjectLinks.repository, startsWith('https://github.com/'));
      expect(ProjectLinks.releases, '${ProjectLinks.repository}/releases');
      expect(ProjectLinks.issues, '${ProjectLinks.repository}/issues');
    });

    test('地址不含空格或中文（原生 Uri.parse 与浏览器都对它更友好）', () {
      for (final url in [
        ProjectLinks.repository,
        ProjectLinks.releases,
        ProjectLinks.issues,
      ]) {
        expect(RegExp(r'^[\x21-\x7E]+$').hasMatch(url), isTrue,
            reason: '$url 含非 ASCII 或空白字符');
      }
    });
  });
}
