import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 「行迹」品牌标记：一条向上的行进轨迹。
///
/// **为什么用手绘而不是现成图标**：
/// 这是 App 图标上的同一个图形，登录页、注册页、启动页必须和图标一致 ——
/// 之前这三个地方各自用 `Icons.directions_run`（一个通用跑步小人），
/// 和桌面图标完全是两个东西，用户反馈「进登录界面那个小人跑的图标
/// 是不是应该改改和 app 图标一致」说的就是这个。
///
/// 画法与 `tools/make_app_icon.py` 保持一致：
/// 三次贝塞尔曲线 + 圆头笔画 + 起点半透明（出发）/ 终点实心（现在）。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 72,
    this.color = Colors.white,
    this.onGradient = true,
  });

  /// 外框边长。内部图形按比例缩放。
  final double size;

  /// 笔画颜色。
  final Color color;

  /// 是否画在半透明圆形底上（登录/注册页的橙色背景上是需要的；
  /// 白底页面则不需要）。
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size(size * 0.56, size * 0.56),
      painter: _TrailPainter(color: color),
    );

    if (!onGradient) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      alignment: Alignment.center,
      child: mark,
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 与图标同一组控制点（比例坐标）
    final p0 = Offset(w * 0.10, h * 0.78);
    final p1 = Offset(w * 0.28, h * 0.22);
    final p2 = Offset(w * 0.78, h * 0.86);
    final p3 = Offset(w * 0.94, h * 0.20);

    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w * 0.155
      ..color = color;

    canvas.drawPath(path, stroke);

    // 起点：半透明（出发地）
    canvas.drawCircle(
      p0,
      w * 0.155 / 2,
      Paint()..color = color.withValues(alpha: 0.45),
    );

    // 终点：实心（当前位置）
    canvas.drawCircle(p3, w * 0.155 * 0.62, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.color != color;
}

/// 品牌头部：标记 + 名称 + 一句话。
///
/// 登录页与注册页共用，保证两个页面视觉完全一致
/// （之前各写一份，出现了字号与间距不一致）。
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.slogan,
    this.markSize = 76,
  });

  final String slogan;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BrandMark(size: markSize),
        const SizedBox(height: AppSpacing.md),
        const Text(
          '行迹',
          style: TextStyle(
            color: AppColors.onPrimary,
            fontSize: AppFontSize.display,
            fontWeight: AppFontWeight.bold,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          slogan,
          style: TextStyle(
            color: AppColors.onPrimary.withValues(alpha: 0.88),
            fontSize: AppFontSize.body,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
