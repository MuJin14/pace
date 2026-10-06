import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 统一错误态：可选标题 + 错误信息 + 重试 / 自定义动作。
///
/// [onRetry] 仍为原有用法（自动生成「重试」按钮）；需要自定义文案或卡片内
/// 联错误时传 [actionLabel] + [onRetry]，或用 [action] 传任意组件。
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title,
    this.actionLabel = '重试',
    this.action,
    this.icon = Icons.error_outline,
  });

  final String message;

  /// 重试回调；为空且未传 [action] 时不显示动作区
  final VoidCallback? onRetry;

  /// 可选标题（如「加载失败」）
  final String? title;

  final String actionLabel;

  /// 自定义动作组件（优先于 [onRetry]）
  final Widget? action;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final Widget? actionWidget = action ??
        (onRetry == null || actionLabel.isEmpty
            ? null
            : ElevatedButton(onPressed: onRetry, child: Text(actionLabel)));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.md),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppFontSize.body,
                color: AppColors.textSecondary,
              ),
            ),
            if (actionWidget != null) ...[
              const SizedBox(height: AppSpacing.md),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }
}
