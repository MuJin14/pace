import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 环形进度：底环 + 进度环 + 中心文字。
///
/// 首页规格：84 尺寸、8 描边、底环白 30%、进度环纯白、中心百分比 17.6/700。
/// 深色（Hero）场景传 `onDark: true`，颜色自动切换到白色系。
class AppProgressRing extends StatelessWidget {
  const AppProgressRing({
    super.key,
    required this.value,
    this.size = 84,
    this.strokeWidth = 8,
    this.color,
    this.trackColor,
    this.text,
    this.textColor,
    this.textSize = AppFontSize.percent,
    this.onDark = false,
    this.semanticLabel,
  });

  /// 进度，0..1（越界自动裁剪）
  final double value;

  final double size;
  final double strokeWidth;

  /// 进度环颜色；深色场景默认白色，浅色场景默认 [AppColors.accentHot]
  final Color? color;

  /// 底环颜色；深色默认白 30%，浅色默认进度色 15%
  final Color? trackColor;

  /// 中心文字；为空时显示百分比
  final String? text;

  final Color? textColor;
  final double textSize;

  /// 深色背景（Hero 渐变卡）场景
  final bool onDark;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // 显式裁剪，避免依赖 num.clamp 的静态类型推断
    final raw = value.isNaN ? 0.0 : value;
    final progress = raw < 0.0 ? 0.0 : (raw > 1.0 ? 1.0 : raw);
    final ringColor = color ?? (onDark ? Colors.white : AppColors.accentHot);
    final track = trackColor ??
        (onDark
            ? Colors.white.withValues(alpha: 0.3)
            : ringColor.withValues(alpha: 0.15));
    final fg = textColor ?? (onDark ? Colors.white : AppColors.textPrimary);
    final label = text ?? '${(progress * 100).round()}%';

    return Semantics(
      label: semanticLabel ?? '进度 $label',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor: track,
                color: ringColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: textSize,
                fontWeight: AppFontWeight.bold,
                color: fg,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
