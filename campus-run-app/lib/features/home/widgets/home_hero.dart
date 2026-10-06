import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_metric_text.dart';
import '../../../core/widgets/app_progress_ring.dart';

/// Hero 空态召唤位虚线规格（设计稿 §3：白底 + 1.5px 橙色虚线，圆角 24）。
const double _dashStroke = 1.5;
const double _dashLength = 6;
const double _dashGap = 4;

/// 空态图标与全宽按钮尺寸（设计稿 §3：图标 56 + 全宽实心按钮 48）。
const double _emptyIconSize = 56;
const double _emptyActionHeight = 48;

/// 今日目标 Hero（数据态）。
///
/// 135° 橙渐变卡（[AppDashboardCard.gradientColors] + [AppRadius.lg]）：
/// 小标题 12.6/500 白 85%、主数字 39.6/700 白 + 单位 15.6 白 70%、
/// 说明 11.6 白 70%、进度环 84（[AppProgressRing] onDark）、白底开始跑步胶囊。
///
/// 数值与文案由首页聚合后传入，组件只负责呈现。
class HomeHeroGoalCard extends StatelessWidget {
  const HomeHeroGoalCard({
    super.key,
    required this.distanceText,
    required this.targetText,
    required this.remainingText,
    required this.weekRunCount,
    required this.progress,
    required this.onStart,
  });

  /// 今日距离（km，1 位小数）。
  final String distanceText;

  /// 每日目标（km，1 位小数）；无有效目标时为 null。
  final String? targetText;

  /// 距达标还差多少（km，1 位小数）；无有效目标时为 null。
  final String? remainingText;

  /// 本周已完成次数。
  final int weekRunCount;

  /// 今日完成度 0..1。
  final double progress;

  final VoidCallback onStart;

  bool get _hasTarget => targetText != null && remainingText != null;

  @override
  Widget build(BuildContext context) {
    return AppDashboardCard(
      gradientColors: AppColors.heroGradient,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.pageWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日目标',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: AppFontWeight.medium,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppMetricText(
                      value: distanceText,
                      unit: 'km',
                      valueSize: AppFontSize.metricHero,
                      unitSize: AppFontSize.unit,
                      color: Colors.white,
                      crossAxisAlignment: CrossAxisAlignment.start,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _subtitle,
                      style: TextStyle(
                        fontSize: AppFontSize.hint,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasTarget) AppProgressRing(value: progress, onDark: true),
            ],
          ),
          const SizedBox(height: AppSpacing.block),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StartRunPill(onTap: onStart),
              if (_hasTarget)
                Text(
                  '还差 $remainingText km 达标',
                  style: TextStyle(
                    fontSize: AppFontSize.hint,
                    fontWeight: AppFontWeight.medium,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String get _subtitle => _hasTarget
      ? '目标 $targetText km · 本周已完成 $weekRunCount 次'
      : '本周已完成 $weekRunCount 次';
}

/// 今日目标 Hero（空态）：白底 + 1.5px 橙色虚线召唤位 + 图标 56 +
/// 「今天还没跑」20/700 + 全宽实心按钮 48。
class HomeEmptyHero extends StatelessWidget {
  const HomeEmptyHero({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AppDashboardCard(
      radius: AppRadius.lg,
      padding: EdgeInsets.zero,
      child: CustomPaint(
        painter: const _DashedRoundedBorder(
          color: AppColors.accentHot,
          strokeWidth: _dashStroke,
          radius: AppRadius.lg,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: AppEmptyHint(
            icon: Icons.directions_run,
            iconSize: _emptyIconSize,
            iconColor: AppColors.accentHot,
            title: '今天还没跑',
            titleSize: AppFontSize.headline,
            description: '完成第一次跑步，点亮今日徽章',
            actionLabel: '开始跑步',
            onAction: onStart,
            actionFullWidth: true,
            actionHeight: _emptyActionHeight,
          ),
        ),
      ),
    );
  }
}

/// 白底胶囊动作：图标 16 + 文字（[AppFontSize.labelLg]/600 观感 → 700）热橙。
class _StartRunPill extends StatelessWidget {
  const _StartRunPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.gap10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, size: AppSpacing.md, color: AppColors.accentHot),
              SizedBox(width: AppSpacing.gap6),
              Text(
                '开始跑步',
                style: TextStyle(
                  fontSize: AppFontSize.labelLg,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.accentHot,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1.5px 橙色虚线圆角召唤位（core/widgets 暂无等价组件）。
class _DashedRoundedBorder extends CustomPainter {
  const _DashedRoundedBorder({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + _dashLength).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorder oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}
