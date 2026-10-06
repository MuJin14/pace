import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_empty_hint.dart';

/// 统一空态（页面级）：大圆形图标 + 标题 + 说明 + 可选动作。
///
/// 设计规范（home_spec §3）：空态必须含召唤语 + 至少一个可点击动作。
/// 区块内空态请用 [AppEmptyHint]；本组件的既有构造签名保持不变，仅新增参数。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
    this.onAction,
    this.iconSize = 40,
    this.iconBoxSize = 88,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// 自定义动作组件（优先于 [actionLabel]）
  final Widget? action;

  /// 动作按钮文案；与 [onAction] 同时提供时自动生成
  final String? actionLabel;

  final VoidCallback? onAction;

  final double iconSize;
  final double iconBoxSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppEmptyHint(
        icon: icon,
        iconSize: iconSize,
        iconBoxSize: iconBoxSize,
        iconColor: AppColors.primary,
        iconBackground: AppColors.primary.withValues(alpha: 0.1),
        title: title,
        titleSize: AppFontSize.title,
        titleWeight: FontWeight.w600,
        description: subtitle,
        descriptionSize: AppFontSize.body,
        action: action,
        actionLabel: actionLabel,
        onAction: onAction,
        padding: const EdgeInsets.all(AppSpacing.xl),
      ),
    );
  }
}
