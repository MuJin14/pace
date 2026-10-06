import 'package:campus_run_app/core/storage/server_address_storage.dart';
import 'package:campus_run_app/core/theme/app_theme.dart';
import 'package:campus_run_app/core/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 头像必须走**缩略图**而不是原图。
///
/// **为什么值得单独测**：头像出现在好友列表、排行榜、聊天、搜索结果等
/// **每一条列表项**里。实测一张原图 239KB，缩到 96px 只有 6.6KB（36 倍）；
/// 服务器上行只有约 0.3MB/s，一屏十几张原图就是几秒钟的「转圈」。
///
/// 这是个很容易被改回去的优化 —— 谁顺手把 `thumb ?? resolved`
/// 换成 `resolved`，界面上不会报错、只是变慢，代码评审也看不出来。
/// 所以用测试把「请求的 URL 必须是缩略图接口」钉死。
void main() {
  /// 取出 UserAvatar 内部真正请求的 URL。
  String requestedUrl(WidgetTester tester) {
    final img = tester.widget<Image>(find.byType(Image));
    final provider = img.image;
    expect(provider, isA<NetworkImage>(),
        reason: '有头像地址时应当走网络图');
    return (provider as NetworkImage).url;
  }

  Future<void> pumpAvatar(
    WidgetTester tester, {
    required String? avatarUrl,
    double size = 44,
    double devicePixelRatio = 3.0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverAddressStorageProvider
              .overrideWithValue(InMemoryServerAddressStorage()),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: devicePixelRatio),
            child: Scaffold(
              body: Center(
                child: UserAvatar(nickname: '张三', avatarUrl: avatarUrl, size: size),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const original =
      'http://122.51.191.145:8080/uploads/avatar/e49a18a1239243a8835f4868bae3fac6.jpg';

  group('头像请求的是缩略图', () {
    testWidgets('不是原图地址', (tester) async {
      await pumpAvatar(tester, avatarUrl: original);
      final url = requestedUrl(tester);

      expect(url, contains('/api/v1/media/thumb'),
          reason: '头像必须走缩略图接口，否则每张 239KB');
      expect(url, isNot(contains('/uploads/avatar/')),
          reason: '不能直接请求原图路径');
    });

    testWidgets('带上原图的相对路径与宽度参数', (tester) async {
      await pumpAvatar(tester, avatarUrl: original, size: 44);
      final url = requestedUrl(tester);

      expect(url, contains('path='));
      expect(url, contains('avatar'));
      expect(url, contains('w='));
    });

    testWidgets('宽度按「显示尺寸 × 设备像素比」取，并归整到 32 的倍数',
        (tester) async {
      // size 44 逻辑 × dpr 3 = 132 物理 -> 归整到 160
      await pumpAvatar(tester, avatarUrl: original, size: 44, devicePixelRatio: 3);
      expect(requestedUrl(tester), contains('w=160'),
          reason: '44×3=132，向上归整到 160');
    });

    testWidgets('高分屏取更大的缩略图（避免发虚）', (tester) async {
      await pumpAvatar(tester, avatarUrl: original, size: 44, devicePixelRatio: 2);
      final w2 = int.parse(
          RegExp(r'w=(\d+)').firstMatch(requestedUrl(tester))!.group(1)!);

      await pumpAvatar(tester, avatarUrl: original, size: 44, devicePixelRatio: 3);
      final w3 = int.parse(
          RegExp(r'w=(\d+)').firstMatch(requestedUrl(tester))!.group(1)!);

      expect(w3, greaterThanOrEqualTo(w2),
          reason: 'dpr 越大需要的物理像素越多');
      // 44×2=88 -> 96 ; 44×3=132 -> 160
      expect(w2, 96);
      expect(w3, 160);
    });

    testWidgets('宽度归整到 32 的倍数（让相邻尺寸命中同一份缓存）',
        (tester) async {
      // dpr=3 下：40×3=120 -> 128；44×3=132 -> 160；46×3=138 -> 160
      // 46 与 44 落在同一档，列表页和资料页就能共用缓存，不重复下载。
      await pumpAvatar(tester, avatarUrl: original, size: 44);
      expect(requestedUrl(tester), contains('w=160'));
      await pumpAvatar(tester, avatarUrl: original, size: 46);
      expect(requestedUrl(tester), contains('w=160'),
          reason: '46 与 44 应当归到同一档');
      await pumpAvatar(tester, avatarUrl: original, size: 40);
      expect(requestedUrl(tester), contains('w=128'));
    });
  });

  group('边界与兜底', () {
    testWidgets('没有头像地址时走首字兜底，不发请求', (tester) async {
      await pumpAvatar(tester, avatarUrl: null);
      expect(find.byType(Image), findsNothing);
      expect(find.text('张'), findsOneWidget);
    });

    testWidgets('空串同样走兜底', (tester) async {
      await pumpAvatar(tester, avatarUrl: '');
      expect(find.byType(Image), findsNothing);
      expect(find.text('张'), findsOneWidget);
    });

    testWidgets('加载完成前先显示首字兜底（避免空洞后突然跳变）', (tester) async {
      await pumpAvatar(tester, avatarUrl: original);
      // 网络图尚未完成时，frameBuilder 应当返回兜底而不是空白
      expect(find.text('张'), findsOneWidget,
          reason: '加载中要有兜底占位，否则列表里是空洞');
    });
  });

  testWidgets('头像圆角裁剪与尺寸正确', (tester) async {
    await pumpAvatar(tester, avatarUrl: original, size: 64);
    final clip = tester.widget<ClipOval>(find.byType(ClipOval));
    expect(clip, isNotNull);
    expect(tester.getSize(find.byType(UserAvatar)), const Size(64, 64));
  });

  testWidgets('兜底底色用品牌渐变（与 App 主题一致）', (tester) async {
    await pumpAvatar(tester, avatarUrl: null);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(UserAvatar),
        matching: find.byType(Container),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    final gradient = deco.gradient as LinearGradient;
    expect(gradient.colors, AppColors.primaryGradient);
  });
}
