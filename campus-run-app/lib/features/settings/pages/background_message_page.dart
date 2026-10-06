import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/battery_optimization.dart';
import '../../../core/theme/app_theme.dart';

/// 「后台消息提醒」说明页。
///
/// ## 这一页的定位：**纯说明 + 自愿设置**
///
/// 它**不做任何自动改动**，也不申请任何权限。原因是评估过更强的方案
/// （前台服务保活）后放弃了：
///
/// > 前台服务必须在通知栏常驻一条通知（Android 硬性要求），
/// > 对一个校园跑步 App 来说，为了消息及时性而长期占用用户的通知栏
/// > 属于强制打扰，不划算。
///
/// ## 为什么还是留了这一页
///
/// 因为**问题真实存在**：Android 会在息屏一段时间后冻结后台应用的网络，
/// WebSocket 被掐断，App 在后台期间收不到实时消息。这是系统行为，
/// 不是 App 的 bug，但用户只会感觉「这 App 收不到消息」。
///
/// 各 ROM 的省电设置路径都不一样、且藏得很深，用户自己基本找不到。
/// 把路径写清楚放在这里，愿意设的用户可以自己设 ——
/// **不设也不影响任何功能**，只是后台消息的及时性差一些。
///
/// ## 关键澄清：消息不会丢
///
/// 用户最担心的是「会不会漏消息」。答案是**不会**：
/// 消息在服务端落库，未读红点在重新打开 App 时会从服务端拉取重建
/// （见 unread_sync_provider）。后台期间没收到的是**实时提醒**，
/// 不是消息本身。
class BackgroundMessagePage extends ConsumerWidget {
  const BackgroundMessagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_batteryStatusProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('后台消息提醒')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageWide,
          AppSpacing.md,
          AppSpacing.pageWide,
          AppSpacing.xl,
        ),
        children: [
          // 先把「消息不会丢」说清楚 —— 这是用户最关心的
          const _Card(
            icon: Icons.mark_email_read_outlined,
            iconColor: AppColors.success,
            title: '消息不会丢',
            body: '好友发的消息都存在服务器上。即使 App 在后台没弹出提醒，'
                '你重新打开时也能看到 —— 那一行会有未读红点。\n'
                '这一页只影响「提醒的及时性」，不影响消息本身。',
          ),
          const SizedBox(height: AppSpacing.md),
          _StatusCard(status: status),
          const SizedBox(height: AppSpacing.lg),
          const _WhyCard(),
          const SizedBox(height: AppSpacing.lg),
          const _ManualStepsCard(),
        ],
      ),
    );
  }
}

/// 电池优化状态。每次被 watch 时查询（invalidate 即刷新）。
final _batteryStatusProvider = FutureProvider<bool>((ref) {
  return BatteryOptimization.isIgnoringOptimizations();
});

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final AsyncValue<bool> status;

  @override
  Widget build(BuildContext context) {
    return status.when(
      loading: () => const _Card(
        icon: Icons.hourglass_empty,
        iconColor: AppColors.textHint,
        title: '正在检查…',
        body: '',
      ),
      error: (e, _) => _Card(
        icon: Icons.info_outline,
        iconColor: AppColors.textHint,
        title: '读取系统设置失败',
        body: '$e\n\n不影响使用，可跳过这一页。',
      ),
      data: (ignoring) {
        if (ignoring) {
          return const _Card(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success,
            title: '后台提醒已就绪',
            body: '系统不会因为省电而限制行迹，在后台也能及时收到好友消息提醒。',
          );
        }
        return const _Card(
          icon: Icons.battery_saver_outlined,
          iconColor: AppColors.primary,
          title: '后台提醒可能延迟',
          body: '系统的省电策略会限制后台应用联网，所以 App 退到后台时'
              '可能收不到即时提醒（消息本身不会丢）。\n'
              '想改善的话，按下面的路径把行迹设为「不受限制」即可。',
        );
      },
    );
  }
}

class _WhyCard extends StatelessWidget {
  const _WhyCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      icon: Icons.help_outline,
      iconColor: AppColors.primary,
      title: '为什么会这样',
      body: '好友消息通过一条常驻连接实时送达。Android 为了省电，'
          '会在息屏一段时间后冻结后台应用的网络，连接断开就收不到即时提醒 —— '
          '这是系统行为，不是行迹的问题，微信等应用也受同样的限制。',
    );
  }
}

class _ManualStepsCard extends StatelessWidget {
  const _ManualStepsCard();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('小米 / 红米（MIUI、HyperOS）',
          '设置 → 应用设置 → 应用管理 → 行迹 → 省电策略 → 无限制\n'
          '另外在「应用管理 → 行迹 → 自启动」里打开'),
      ('华为 / 荣耀', '设置 → 应用 → 应用启动管理 → 行迹 → 改为「手动管理」\n'
          '并把「允许后台活动」打开'),
      ('OPPO / 一加 / realme', '设置 → 电池 → 更多设置 → 睡眠待机优化 → 关闭\n'
          '并在「应用管理 → 行迹 → 耗电管理」里允许后台运行'),
      ('vivo / iQOO', '设置 → 电池 → 后台高耗电 → 允许行迹\n'
          '并在「i 管家 → 自启动」里打开'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '想改善的话，按机型设置',
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            '完全自愿 —— 不设也不影响任何功能。',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (title, detail) in steps) ...[
            Text(
              title,
              style: const TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: AppFontWeight.medium,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          OutlinedButton(
            onPressed: () => BatteryOptimization.openSettings(),
            child: const Text('打开系统电池优化设置'),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: AppFontSize.caption,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
