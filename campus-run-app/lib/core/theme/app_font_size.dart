/// 字号体系：语义桶（既有 5 档）+ 设计稿精确档 + 大数字（metric）系列。
///
/// 取值来自 `design/home_spec.png`（《行迹 App·首页信息架构优化规格》§2）。
/// 设计稿实际用到 9.6 / 10.6 / 11.6 / 12.6 / 13.6 / 14.6 / 15.6 / 16.6 /
/// 17.6 / 23.6 / 39.6 等中间档，此处全部 token 化，页面不得再写裸 fontSize。
///
/// 命名约定：
/// - 文案类：micro → tiny → hint → label → labelLg → subtitle → unit → greeting → percent
/// - 数字类：metric → metricHero → metricLg → metricXl
/// - 语义桶：caption / body / title / headline / display（既有名称与取值保持不变）
class AppFontSize {
  AppFontSize._();

  // ── 1. 语义桶（既有 5 档，数值不变）────────────────────────
  /// 12：说明、时间戳、提示
  static const double caption = 12;

  /// 14：正文、列表副标题
  static const double body = 14;

  /// 16：标题
  static const double title = 16;

  /// 20：区块标题、重点数字
  static const double headline = 20;

  /// 28：首页大数字
  static const double display = 28;

  // ── 2. 设计稿精确档（文案）────────────────────────────────
  /// 9.6：迷你柱状图星期标签
  static const double micro = 9.6;

  /// 10.6：环比 chip、极小角标
  static const double tiny = 10.6;

  /// 11.6：顶栏日期、卡片副说明（最常用小字）
  static const double hint = 11.6;

  /// 12.6：标签、Hero 小标题、卡片标题
  static const double label = 12.6;

  /// 13.6：列表主标题、胶囊按钮文字
  static const double labelLg = 13.6;

  /// 14.6：卡片主标题（今日运动 / 本周跑量）
  static const double subtitle = 14.6;

  /// 15.6：单位、百分比强调
  static const double unit = 15.6;

  /// 16.6：顶栏问候语
  static const double greeting = 16.6;

  /// 17.6：环形进度百分比、空态标题
  static const double percent = 17.6;

  // ── 3. 大数字（metric）系列 ───────────────────────────────
  /// 23.6：三栏统计大数字（今日运动 距离 / 时长 / 配速）
  static const double metric = 23.6;

  /// 39.6：Hero 主数字（今日目标距离）
  static const double metricHero = 39.6;

  /// 42：运动详情页距离
  static const double metricLg = 42;

  /// 44：跑步进行中 / 跑步结果页距离
  static const double metricXl = 44;

  // ── 4. 产品指定档 ────────────────────────────────────────
  /// 17：主按钮文字
  static const double button = 17;

  /// 32：启动页 Logo
  static const double splash = 32;

  /// 全部字号（升序），便于自检设计稿覆盖度。
  static const List<double> scale = [
    micro,
    tiny,
    hint,
    caption,
    label,
    labelLg,
    body,
    subtitle,
    unit,
    title,
    greeting,
    percent,
    headline,
    metric,
    display,
    splash,
    metricHero,
    metricLg,
    metricXl,
  ];
}
