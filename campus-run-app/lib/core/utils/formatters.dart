/// 展示用格式化工具。距离/时长/配速/速度/日期统一在此处理。
class Formatters {
  Formatters._();

  /// 专属 ID 的展示文案：`ID 12345678`。
  ///
  /// 后端存的是纯数字（8 位，左侧补零），历史数据可能带 `CR-` 前缀，
  /// 这里统一剥掉，保证界面上一眼看出「这是对方要输入的 ID」，
  /// 而不是让人以为要连字母一起输。
  static String uniqueId(String raw) {
    final digits = raw.startsWith('CR-') ? raw.substring(3) : raw;
    return 'ID $digits';
  }

  /// 距离：米 → `5.23 km` / `850 m`
  static String distance(int meters) {
    if (meters < 1000) return '$meters m';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(km >= 100 ? 1 : 2)} km';
  }

  /// 时长：秒 → `1:02:30` / `42:30`
  static String duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  /// 配速：秒/公里 → `6'30"`；空值返回占位。
  static String pace(int? secondsPerKm) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '—';
    final m = secondsPerKm ~/ 60;
    final s = secondsPerKm % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  /// 速度：km/h → `5.2 km/h`
  static String speed(double? kmh) {
    if (kmh == null) return '—';
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  /// 卡路里 → `320.5 kcal`
  static String calories(double? kcal) {
    if (kcal == null) return '—';
    return '${kcal.toStringAsFixed(kcal == kcal.roundToDouble() ? 0 : 1)} kcal';
  }

  /// 后端 `yyyy-MM-dd HH:mm:ss` → `9月22日 20:00`。解析失败原样返回。
  static String dateTime(String? s) {
    if (s == null || s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}月${dt.day}日 $hh:$mm';
  }

  /// 后端日期/时间串 → `9月22日`
  static String monthDay(String? s) {
    final dt = DateTime.tryParse(s ?? '');
    if (dt == null) return s ?? '—';
    return '${dt.month}月${dt.day}日';
  }

  /// 后端 `yyyy-MM-dd HH:mm:ss` → `2026-09-23 上午 8:30`（中文上午/下午）。
  static String dateTimeCn(String? s) {
    if (s == null || s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final period = dt.hour < 12 ? '上午' : '下午';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    final date = '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
    return '$date $period $h:$mm';
  }

  /// 毫秒时间戳 → `HH:mm`（聊天用）
  static String timeOfEpoch(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// 相对时间：今天 / 昨天 显示 `今天 07:12`，更早显示 `9月30日 06:55`。
  ///
  /// 抽到公共位置是因为「首页近期运动」和「他人主页的运动记录」都要用，
  /// 各自实现会导致同一条记录在两个页面显示成不同文案。
  static String relativeTime(String? s) {
    final dt = DateTime.tryParse(s ?? '');
    if (dt == null) return s ?? '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (day == today) return '今天 $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hh:$mm';
    return '${dt.month}月${dt.day}日 $hh:$mm';
  }
}
