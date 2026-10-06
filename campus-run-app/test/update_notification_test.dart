import 'package:campus_run_app/core/update/pending_update_provider.dart';
import 'package:campus_run_app/data/repositories/app_version_repository.dart';
import 'package:campus_run_app/features/notifications/providers/notifications_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「新版本提醒放进右上角通知」这套设计。
///
/// ## 为什么改成通知而不是启动弹窗
///
/// 原先是启动检查 → 直接弹对话框。两个问题：
///   1. **打扰**：冷启动弹「要更新吗」，而用户此刻往往只想看一眼步数；
///   2. **容易被误关**：条件反射点「稍后」之后再也没有入口 ——
///      更新提示彻底形同虚设。
///
/// 现在：有新版 → 铃铛红点；点进通知页 → 看到「发现新版本」；
/// 点那一条才弹对话框。入口常驻，不会被误关掉。
///
/// 这一组测试守的就是「入口确实会出现」—— 因为如果 [pendingUpdateProvider]
/// 没被写进去，通知里就没有这一条，而**界面上看不出任何异常**，
/// 表现就是「更新提示又没了」。
void main() {
  /// 造一份「有新版本」的信息。
  AppVersionInfo newVersion({
    String latest = '1.9.9',
    String minSupported = '',
  }) =>
      AppVersionInfo(
        latest: latest,
        minSupported: minSupported,
        changelog: '修了一些问题',
        apkReady: true,
        apkUrl: 'http://example.com/a.apk',
        apkSizeBytes: 1048576,
      );

  group('待更新状态', () {
    test('初始为空（没有新版本时不打扰）', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(pendingUpdateProvider), isNull);
    });

    test('记录后能读到，且带上「是否强制」', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(pendingUpdateProvider.notifier)
          .found(newVersion(), mandatory: false);

      final p = c.read(pendingUpdateProvider);
      expect(p, isNotNull);
      expect(p!.latest, '1.9.9');
      expect(p.mandatory, isFalse);
    });

    test('同一版本重复记录不产生额外状态变更（避免通知列表无谓刷新）', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      var rebuilds = 0;
      c.listen(pendingUpdateProvider, (_, __) => rebuilds++);

      final n = c.read(pendingUpdateProvider.notifier);
      n.found(newVersion(), mandatory: false);
      n.found(newVersion(), mandatory: false);
      n.found(newVersion(), mandatory: false);

      expect(rebuilds, 1, reason: '内容没变就不该反复通知监听者');
    });

    test('阈值变化（普通 → 强制）要重新记录', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final n = c.read(pendingUpdateProvider.notifier);
      n.found(newVersion(), mandatory: false);
      n.found(newVersion(minSupported: '1.5.0'), mandatory: true);

      expect(c.read(pendingUpdateProvider)!.mandatory, isTrue);
    });

    test('clear 之后回到「没有更新」', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final n = c.read(pendingUpdateProvider.notifier);
      n.found(newVersion(), mandatory: false);
      n.clear();

      expect(c.read(pendingUpdateProvider), isNull);
    });
  });

  group('通知聚合里的「发现新版本」条目', () {
    test('有新版本时通知里出现这一条，且排在最前', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(pendingUpdateProvider.notifier)
          .found(newVersion(latest: '1.9.9'), mandatory: false);

      final items = c.read(notificationsProvider);
      expect(items, isNotEmpty, reason: '有新版就必须有通知条目，否则铃铛不亮');
      expect(items.first.type, AppNotificationType.appUpdate,
          reason: '更新是会改变 App 本身的事，应当排在最前');
      expect(items.first.title, contains('1.9.9'));
    });

    test('强制更新时文案不同（说清「必须」）', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(pendingUpdateProvider.notifier)
          .found(newVersion(minSupported: '1.5.0'), mandatory: true);

      final item = c.read(notificationsProvider).first;
      expect(item.title, contains('必须'));
      expect(item.description, contains('立即'));
    });

    test('没有新版本时通知里没有更新条目', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final items = c.read(notificationsProvider);
      expect(
        items.where((n) => n.type == AppNotificationType.appUpdate),
        isEmpty,
      );
    });

    test('更新条目**不带 route**（它是就地弹对话框，不是跳页）', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(pendingUpdateProvider.notifier)
          .found(newVersion(), mandatory: false);

      final item = c.read(notificationsProvider).first;
      // 带 route 的话会被 _NotificationTile 当成普通跳转，
      // 点下去跳到某个页面而不是弹更新框。
      expect(item.route, isNull);
    });

    test('铃铛红点会因为这条件亮起', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(c.read(hasNotificationsProvider), isFalse);

      c.read(pendingUpdateProvider.notifier)
          .found(newVersion(), mandatory: false);

      expect(c.read(hasNotificationsProvider), isTrue,
          reason: '右上角铃铛必须出现红点，否则用户看不到更新入口');
    });
  });
}
