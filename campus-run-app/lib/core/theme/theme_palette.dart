import 'package:flutter/material.dart';

/// 全局色板：马卡龙蜜桃橙主色 + 薄荷辅助。
/// 风格：Keep 的活力 + 微信的克制。
class AppColors {
  AppColors._();

  // ── 品牌主色：马卡龙蜜桃橙 ─────────────
  /// 主色：马卡龙蜜桃橙（品牌、选中态、装饰）
  static const Color primary = Color(0xFFFF8C42);

  /// 主色浅：马卡龙奶油橙（装饰、标签底、选中背景，不做按钮底）
  static const Color primaryLight = Color(0xFFFFDAC1);

  /// 主色深：按下态、深色强调、主按钮底
  static const Color primaryDark = Color(0xFFE56A1E);

  /// 品牌渐变（头像 / 启动页）
  static const List<Color> primaryGradient = [
    Color(0xFFFF8C42),
    Color(0xFFE56A1E),
  ];

  // ── 次色：薄荷绿 ──────────────────────
  /// 薄荷绿（数据可视化、次按钮）
  static const Color secondary = Color(0xFF7DD3C0);

  /// 马卡龙薄荷（标签底、徽章）
  static const Color secondaryLight = Color(0xFFC8EFE7);

  // ── 功能色 ────────────────────────────
  static const Color run = Color(0xFFFF8C42); // 跑步橙（与主色一致）
  static const Color ride = Color(0xFF5B9BF5); // 骑行蓝
  static const Color gold = Color(0xFFF59E0B); // 奖牌 / 前三
  static const Color danger = Color(0xFFEF4444); // 错误 / 删除
  static const Color success = Color(0xFF34C08B); // 成功

  // ── 背景与卡片 ────────────────────────
  static const Color background = Color(0xFFFDF9F5); // 页面底（极浅奶油）
  static const Color card = Color(0xFFFFFFFF); // 卡片（纯白）
  static const Color surface = Color(0xFFF5F0EA); // 浅灰奶油（输入框、灰块）
  static const Color divider = Color(0xFFECE7E0); // 分割线

  // ── 文字 ──────────────────────────────
  static const Color textPrimary = Color(0xFF2E2419); // 深咖（标题 / 正文）
  static const Color textSecondary = Color(0xFF8C8075); // 灰咖（副文本）
  static const Color textHint = Color(0xFFB8AFA4); // 浅（提示 / 时间戳）
  static const Color onPrimary = Color(0xFFFFFFFF); // 主色上的文字
  static const Color onAccent = Color(0xFFFFFFFF); // 保留备用（当前无独立 accent）

  // ── 首页规格语义色（design/home_spec.png §2）────────────
  /// 热橙强调：#FF7A2E（今日柱、大数字强调、胶囊按钮）
  static const Color accentHot = Color(0xFFFF7A2E);

  /// Hero 渐变浅端：#FF9E5E
  static const Color heroStart = Color(0xFFFF9E5E);

  /// Hero 卡片 135° 橙渐变（浅端 → 热橙）
  static const List<Color> heroGradient = [Color(0xFFFF9E5E), Color(0xFFFF7A2E)];

  /// Hero 卡片橙色柔光阴影（20% 热橙）
  static const Color heroShadow = Color(0x33FF7A2E);

  /// 柱状图·已过日：#FFC79A
  static const Color barPast = Color(0xFFFFC79A);

  /// 柱状图·未跑 / 未来日：#F2EDE8
  static const Color barEmpty = Color(0xFFF2EDE8);

  /// 环比正向绿：#2FA36B
  static const Color deltaUp = Color(0xFF2FA36B);

  /// 图标底·暖黄（校园榜）：#FFF6E6
  static const Color iconBgWarm = Color(0xFFFFF6E6);

  /// 图标底·浅橙（近期运动）：#FFF1E6
  static const Color iconBgPeach = Color(0xFFFFF1E6);

  /// chip 绿底（较昨日）：#EAF6EF
  static const Color chipGreenBg = Color(0xFFEAF6EF);

  /// chip 红底（环比负向，由 [chipGreenBg] 派生，设计稿未定义）
  static const Color chipRedBg = Color(0xFFFDECEC);

  /// 进度轨道（目标进度条底色）：#F5EDE6
  static const Color progressTrack = Color(0xFFF5EDE6);

  /// [progressTrack] 别名：目标进度条轨道
  static const Color goalTrack = progressTrack;

  /// 列表分隔线（极浅）：#F5F0EB
  static const Color dividerLight = Color(0xFFF5F0EB);

  /// 图标盒描边：#F0E8E0
  static const Color borderLight = Color(0xFFF0E8E0);

  /// 奖牌 / 前三：#E8A33D
  static const Color medal = Color(0xFFE8A33D);

  // ── 排行榜名次色 ──────────────────────────────────────────
  /// 金牌（与 [medal] 同值）
  static const Color rankGold = Color(0xFFE8A33D);

  /// 银牌
  static const Color rankSilver = Color(0xFF9BA3AE);

  /// 铜牌
  static const Color rankBronze = Color(0xFFC98A5B);
}
