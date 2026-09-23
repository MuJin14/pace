/// 展示用格式化工具。距离/时长/配速/速度/日期统一在此处理。
class Formatters {
  Formatters._();

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

  /// 毫秒时间戳 → `HH:mm`（聊天用）
  static String timeOfEpoch(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
