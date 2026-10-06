/// 间距 token：4 基准梯度 + 设计稿精确值。
///
/// 取值来自 `design/home_spec.png`（《校园跑 App·首页信息架构优化规格》§2）：
/// 首页水平内边距 20、区块间距 18、卡片内边距 16、列表项垂直 14、
/// 头像与文字 12、数字与标签 6。
///
/// 约定：既有 token（xs / sm / md / lg / page）名称与取值保持不变，
/// 只做新增，避免影响已落盘页面。
class AppSpacing {
  AppSpacing._();

  // ── 4 基准梯度 ────────────────────────────────────────────
  /// 2：同一行内极小间隔（如数字与单位、标签与角标）
  static const double xxs = 2;

  /// 4：图标与文字、标签内边距
  static const double xs = 4;

  /// 8：相关元素分组
  static const double sm = 8;

  /// 12：区块标题与内容、头像与文字
  static const double smLg = 12;

  /// 16：卡片内边距、列表项间距
  static const double md = 16;

  /// 24：区块之间
  static const double lg = 24;

  /// 32：页面级留白、空态内边距
  static const double xl = 32;

  /// 40：Hero / 大留白区域
  static const double xxl = 40;

  // ── 设计稿精确值（首页规格 §2）────────────────────────────
  /// 6：数字与标签、柱状图与日期标签
  static const double gap6 = 6;

  /// 10：卡片内小间隔（胶囊按钮垂直内边距）
  static const double gap10 = 10;

  /// 14：列表项垂直内边距
  static const double gap14 = 14;

  /// 18：首页区块间距（设计稿：每个区块之间 18）
  static const double block = 18;

  /// 20：首页水平内边距（设计稿：水平内边距 20）；也用于空态图标与文案间距
  static const double pageWide = 20;

  /// 页面左右统一边距（既有：列表页沿用 16；首页用 [pageWide]）
  static const double page = 16;

  /// 全部间距（升序），便于自检设计稿覆盖度。
  static const List<double> scale = [
    xxs,
    xs,
    gap6,
    sm,
    gap10,
    smLg,
    gap14,
    md,
    block,
    pageWide,
    lg,
    xl,
    xxl,
  ];
}
