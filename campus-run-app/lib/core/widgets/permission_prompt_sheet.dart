import 'package:flutter/material.dart';

import '../permissions/app_permission_service.dart';
import '../theme/app_theme.dart';

/// 启动时的权限说明卡。
///
/// **为什么先说明再弹系统框**：直接弹系统权限框时，用户不知道 App 要干什么，
/// 拒绝率反而更高。原来的代码把这个顾虑处理成了「推迟到相关页面再申请」，
/// 结果在通知权限上形成死循环（不进聊天页 → 拿不到权限 → 收不到消息 →
/// 更不会进聊天页，见 [AppPermissionService] 的说明）。
///
/// 正确做法是**先把用途讲清楚，再申请** —— 顾虑是对的，解法不是推迟。
///
/// 只在**确实缺权限**时出现；权限齐全时完全不打扰。
class PermissionPromptSheet extends StatefulWidget {
  const PermissionPromptSheet({super.key, required this.gaps});

  final PermissionGaps gaps;

  /// 弹出说明卡。返回用户是否点了「允许」。
  static Future<bool> show(BuildContext context, PermissionGaps gaps) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      // 不用 isScrollControlled：内容很短，固定高度更稳
      backgroundColor: Colors.transparent,
      builder: (_) => PermissionPromptSheet(gaps: gaps),
    );
    return result ?? false;
  }

  @override
  State<PermissionPromptSheet> createState() => _PermissionPromptSheetState();
}

class _PermissionPromptSheetState extends State<PermissionPromptSheet> {
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    final svc = AppPermissionService.instance;
    try {
      // 顺序申请，不要并发：两个系统框同时弹会互相干扰
      // （Android 会把后一个排到前一个之后，日志里看起来像卡住）。
      if (widget.gaps.notification) {
        final ok = await svc.requestNotificationPermission();
        debugPrint('[权限] 通知权限申请结果: $ok');
      }
      if (widget.gaps.location) {
        final perm = await svc.requestLocationPermission();
        debugPrint('[权限] 定位权限申请结果: $perm');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '还差两个权限',
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '开一下这两个，行迹才能正常工作',
            style: TextStyle(
              fontSize: AppFontSize.body,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          if (widget.gaps.notification)
            const _PermissionRow(
              icon: Icons.notifications_active_outlined,
              title: '通知',
              // 说明「不给会怎样」比说明「给了能怎样」更有说服力
              desc: '好友发消息时才能提醒你。不给的话，只有打开 App 进到聊天页\n才会看到新消息 —— 退到后台就完全收不到。',
            ),
          if (widget.gaps.notification && widget.gaps.location)
            const SizedBox(height: AppSpacing.md),
          if (widget.gaps.location)
            _PermissionRow(
              icon: Icons.location_on_outlined,
              title: '定位',
              desc: widget.gaps.locationDeniedForever
                  ? '记录跑步轨迹必需。你之前拒绝过定位权限，\n需要到系统设置里手动打开。'
                  : '记录跑步轨迹必需。只在运动时采集，\n不会在后台偷偷定位。',
            ),

          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('暂不'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : _request,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('允许'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Center(
            child: Text(
              '随时可以在「我的 → 权限」里重新开启',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
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
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: AppFontSize.caption,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
