import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 空态布局：column = 居中纵向（整块空态）；row = 左图标右文案（区块内空态）。
enum AppEmptyHintLayout { column, row }

/// 统一空态：图标 + 标题 + 说明 + 可选动作。
///
/// 设计规范（home_spec §3 硬性要求）：空态必须包含召唤语 + 至少一个可点击动作，
/// 禁止单独出现「0」「—」「还没有」；同一屏最多保留 2 处空态。
/// 页面级空态用 [EmptyState]（88 圆形图标 + 32 内边距），区块内空态用本组件。
class AppEmptyHint extends StatelessWidget {
  const AppEmptyHint({
    super.key,
    required this.title,
    this.icon,
    this.description,
    this.actionLabel,
    this.onAction,
    this.action,
    this.layout = AppEmptyHintLayout.column,
    this.iconSize = 28,
    this.iconBoxSize,
    this.iconColor = AppColors.accentHot,
    this.iconBackground,
    this.iconShape = BoxShape.circle,
    this.titleSize = AppFontSize.percent,
    this.titleWeight = AppFontWeight.bold,
    this.titleColor = AppColors.textPrimary,
    this.descriptionSize = AppFontSize.label,
    this.descriptionColor = AppColors.textSecondary,
    this.textAlign,
    this.padding = EdgeInsets.zero,
    this.iconGap = AppSpacing.pageWide,
    this.descriptionGap = AppSpacing.sm,
    this.actionGap = AppSpacing.pageWide,
    this.actionFullWidth = false,
    this.actionHeight = 40,
  });

  /// 召唤语标题（必填），如「今天还没跑」
  final String title;

  final IconData? icon;

  /// 一行说明，如「完成第一次跑步，点亮今日徽章」
  final String? description;

  /// 动作按钮文案；与 [onAction] 同时提供时自动生成胶囊按钮
  final String? actionLabel;

  /// 动作按钮回调
  final VoidCallback? onAction;

  /// 自定义动作组件（优先于 [actionLabel]）
  final Widget? action;

  final AppEmptyHintLayout layout;

  final double iconSize;

  /// 图标圆底尺寸；为空则只显示裸图标（首页 Hero 空态 56 裸图标）
  final double? iconBoxSize;

  final Color iconColor;

  /// 图标底颜色；为空时用 [AppColors.iconBgPeach]
  final Color? iconBackground;

  final BoxShape iconShape;

  final double titleSize;
  final FontWeight titleWeight;
  final Color titleColor;

  final double descriptionSize;
  final Color descriptionColor;

  /// 文案对齐；为空时 column 居中、row 左对齐
  final TextAlign? textAlign;

  final EdgeInsetsGeometry padding;

  /// column 布局：图标与标题的间距
  final double iconGap;

  /// 标题与说明的间距
  final double descriptionGap;

  /// 文案与动作的间距
  final double actionGap;

  /// 动作按钮是否撑满宽度（整块空态用 48 高全宽按钮）
  final bool actionFullWidth;

  final double actionHeight;

  @override
  Widget build(BuildContext context) {
    final align =
        textAlign ??
        (layout == AppEmptyHintLayout.row ? TextAlign.start : TextAlign.center);
    final actionWidget = _buildAction();

    final texts = <Widget>[
      Text(
        title,
        textAlign: align,
        style: TextStyle(
          fontSize: titleSize,
          fontWeight: titleWeight,
          color: titleColor,
        ),
      ),
      if (description != null) ...[
        SizedBox(height: descriptionGap),
        Text(
          description!,
          textAlign: align,
          style: TextStyle(
            fontSize: descriptionSize,
            fontWeight: AppFontWeight.regular,
            color: descriptionColor,
          ),
        ),
      ],
    ];

    if (layout == AppEmptyHintLayout.row) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            if (icon != null) ...[
              _buildIcon(),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: texts,
              ),
            ),
            if (actionWidget != null) ...[
              const SizedBox(width: AppSpacing.sm),
              actionWidget,
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            _buildIcon(),
            SizedBox(height: iconGap),
          ],
          ...texts,
          if (actionWidget != null) ...[
            SizedBox(height: actionGap),
            actionWidget,
          ],
        ],
      ),
    );
  }

  Widget _buildIcon() {
    final glyph = Icon(icon, size: iconSize, color: iconColor);
    final boxSize = iconBoxSize;
    if (boxSize == null) return glyph;
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        color: iconBackground ?? AppColors.iconBgPeach,
        shape: iconShape,
      ),
      child: Center(child: glyph),
    );
  }

  Widget? _buildAction() {
    if (action != null) return action;
    if (actionLabel == null || onAction == null) return null;

    final button = FilledButton(
      onPressed: onAction,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentHot,
        foregroundColor: AppColors.onPrimary,
        minimumSize: Size(0, actionHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageWide),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        textStyle: const TextStyle(
          fontSize: AppFontSize.labelLg,
          fontWeight: AppFontWeight.bold,
        ),
      ),
      child: Text(actionLabel!),
    );

    if (!actionFullWidth) return button;
    // 整块空态：全宽按钮（默认 actionHeight 40 + 8 = 48，符合设计稿）
    return SizedBox(
      width: double.infinity,
      height: actionHeight + AppSpacing.sm,
      child: button,
    );
  }
}
