import 'package:campus_run_app/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Formatters` 单元测试：覆盖 0 / 负数 / 超大值 / null / 非法字符串等边界。
void main() {
  group('Formatters.relativeTime（首页与他人主页共用）', () {
    test('今天的记录显示「今天 HH:mm」', () {
      final now = DateTime.now();
      final t = DateTime(now.year, now.month, now.day, 7, 5);
      expect(Formatters.relativeTime(t.toIso8601String()), '今天 07:05');
    });

    test('昨天的记录显示「昨天 HH:mm」', () {
      final y = DateTime.now().subtract(const Duration(days: 1));
      final t = DateTime(y.year, y.month, y.day, 18, 30);
      expect(Formatters.relativeTime(t.toIso8601String()), '昨天 18:30');
    });

    test('更早的记录显示 M月d日 HH:mm', () {
      // 取 10 天前，确保不会跨到「今天/昨天」分支
      final d = DateTime.now().subtract(const Duration(days: 10));
      final t = DateTime(d.year, d.month, d.day, 6, 55);
      expect(
        Formatters.relativeTime(t.toIso8601String()),
        '${d.month}月${d.day}日 06:55',
      );
    });

    test('null / 非法字符串原样返回，不抛异常', () {
      expect(Formatters.relativeTime(null), '');
      expect(Formatters.relativeTime('not-a-date'), 'not-a-date');
    });
  });

  group('Formatters.distance', () {
    test('不足 1000 米按米显示', () {
      expect(Formatters.distance(0), '0 m');
      expect(Formatters.distance(1), '1 m');
      expect(Formatters.distance(850), '850 m');
      expect(Formatters.distance(999), '999 m');
    });

    test('1000 米及以上按公里显示，保留 2 位小数', () {
      expect(Formatters.distance(1000), '1.00 km');
      expect(Formatters.distance(5230), '5.23 km');
      expect(Formatters.distance(1234), '1.23 km');
    });

    test('超过 100 km 只保留 1 位小数', () {
      expect(Formatters.distance(100000), '100.0 km');
      expect(Formatters.distance(123456789), '123456.8 km');
    });

    test('99999 米因四舍五入显示为 100.00 km（精度判定用未取整值）', () {
      // 现状记录：km >= 100 的判断发生在 round 之前（99.999 < 100），
      // 于是 99999 m → '100.00 km'，而 100000 m → '100.0 km'，两者不一致。
      expect(Formatters.distance(99999), '100.00 km');
    });

    test('负数按米显示，不抛异常', () {
      expect(Formatters.distance(-1), '-1 m');
      expect(Formatters.distance(-999), '-999 m');
      expect(Formatters.distance(-1000), '-1000 m');
    });

    test('int 最大值（2147483647 米）取 1 位小数', () {
      expect(Formatters.distance(2147483647), '2147483.6 km');
    });
  });

  group('Formatters.duration', () {
    test('不足 1 小时为 m:ss（分钟不补零）', () {
      expect(Formatters.duration(0), '0:00');
      expect(Formatters.duration(59), '0:59');
      expect(Formatters.duration(60), '1:00');
      expect(Formatters.duration(2530), '42:10');
      expect(Formatters.duration(3599), '59:59');
    });

    test('1 小时及以上为 h:mm:ss', () {
      expect(Formatters.duration(3600), '1:00:00');
      expect(Formatters.duration(3661), '1:01:01');
      expect(Formatters.duration(86399), '23:59:59');
      expect(Formatters.duration(90061), '25:01:01');
    });

    test('负数输入产生无意义结果（现状记录，业务上不应传入）', () {
      // Dart 的 % / ~/ 对负数按向下取整：-60 → h=0, m=59, s=0。
      expect(Formatters.duration(-1), '59:59');
      expect(Formatters.duration(-60), '59:00');
    });
  });

  group('Formatters.pace', () {
    test('null / 0 / 负数返回占位', () {
      expect(Formatters.pace(null), '—');
      expect(Formatters.pace(0), '—');
      expect(Formatters.pace(-1), '—');
      expect(Formatters.pace(-390), '—');
    });

    test('秒/公里格式化为基础 m\'ss"', () {
      expect(Formatters.pace(1), '0\'01"');
      expect(Formatters.pace(59), '0\'59"');
      expect(Formatters.pace(60), '1\'00"');
      expect(Formatters.pace(390), '6\'30"');
      expect(Formatters.pace(3599), '59\'59"');
    });

    test('超大值不省略，分钟数直接展开', () {
      expect(Formatters.pace(3600), '60\'00"');
      expect(Formatters.pace(2147483647), '35791394\'07"');
    });
  });

  group('Formatters.speed', () {
    test('null 返回占位，数值保留 1 位小数', () {
      expect(Formatters.speed(null), '—');
      expect(Formatters.speed(0), '0.0 km/h');
      expect(Formatters.speed(5.25), '5.3 km/h');
      expect(Formatters.speed(-3.14), '-3.1 km/h');
    });

    test('超大值 / NaN / Infinity 不抛异常', () {
      expect(Formatters.speed(1e9), '1000000000.0 km/h');
      expect(Formatters.speed(double.nan), 'NaN km/h');
      expect(Formatters.speed(double.infinity), 'Infinity km/h');
    });
  });

  group('Formatters.calories', () {
    test('null 返回占位；整数千卡不带小数', () {
      expect(Formatters.calories(null), '—');
      expect(Formatters.calories(0), '0 kcal');
      expect(Formatters.calories(320.0), '320 kcal');
      expect(Formatters.calories(-12.0), '-12 kcal');
      expect(Formatters.calories(1e9), '1000000000 kcal');
    });

    test('非整数千卡保留 1 位小数（含 0.5 进位边界）', () {
      expect(Formatters.calories(320.5), '320.5 kcal');
      expect(Formatters.calories(320.4), '320.4 kcal');
      expect(Formatters.calories(-12.5), '-12.5 kcal');
    });

    test('NaN 不抛异常', () {
      expect(Formatters.calories(double.nan), 'NaN kcal');
    });
  });

  group('Formatters.dateTime', () {
    test('null / 空串返回占位', () {
      expect(Formatters.dateTime(null), '—');
      expect(Formatters.dateTime(''), '—');
    });

    test('解析成功输出 M月d日 HH:mm', () {
      expect(Formatters.dateTime('2026-09-22 20:00:00'), '9月22日 20:00');
      expect(Formatters.dateTime('2026-09-22T08:05:00'), '9月22日 08:05');
      expect(Formatters.dateTime('2026-09-22'), '9月22日 00:00');
      expect(Formatters.dateTime('2026-01-05 09:07:00'), '1月5日 09:07');
    });

    test('无法解析的字符串原样返回', () {
      expect(Formatters.dateTime('not-a-date'), 'not-a-date');
      expect(Formatters.dateTime('2026/09/22 20:00'), '2026/09/22 20:00');
    });

    test('月份/日期越界会被 DateTime 归一化（现状记录）', () {
      // DateTime.tryParse 不拒绝越界值：2026-13-45 → 2027-02-14。
      expect(Formatters.dateTime('2026-13-45'), '2月14日 00:00');
    });
  });

  group('Formatters.uniqueId（专属 ID 展示）', () {
    test('纯数字 ID 加 ID 前缀，一眼看出是要输入的编号', () {
      expect(Formatters.uniqueId('04231786'), 'ID 04231786');
      expect(Formatters.uniqueId('12345678'), 'ID 12345678');
    });

    test('历史 CR- 前缀会被剥掉，界面上不再出现两种写法', () {
      expect(Formatters.uniqueId('CR-04231786'), 'ID 04231786');
      expect(Formatters.uniqueId('CR-12345678'), 'ID 12345678');
    });

    test('只剥开头的前缀，不误伤内容里出现的字母', () {
      expect(Formatters.uniqueId('1234CR5678'), 'ID 1234CR5678');
    });

    test('空串不崩', () {
      expect(Formatters.uniqueId(''), 'ID ');
    });
  });

  group('Formatters.monthDay', () {
    test('null 返回占位', () {
      expect(Formatters.monthDay(null), '—');
    });

    test('解析成功输出 M月d日', () {
      expect(Formatters.monthDay('2026-09-22'), '9月22日');
      expect(Formatters.monthDay('2026-09-22 20:00:00'), '9月22日');
      expect(Formatters.monthDay('2026-01-05T09:07:00'), '1月5日');
    });

    test('无法解析的字符串原样返回', () {
      expect(Formatters.monthDay('bad'), 'bad');
    });

    test('空串返回空串（与 dateTime 的占位不一致，现状记录）', () {
      expect(Formatters.monthDay(''), '');
    });
  });

  group('Formatters.dateTimeCn', () {
    test('null / 空串返回占位', () {
      expect(Formatters.dateTimeCn(null), '—');
      expect(Formatters.dateTimeCn(''), '—');
    });

    test('上午/下午按 12 小时制换算，0 点与 12 点都显示 12', () {
      expect(Formatters.dateTimeCn('2026-09-23 08:30:00'), '2026-09-23 上午 8:30');
      expect(Formatters.dateTimeCn('2026-09-23 00:05:00'),
          '2026-09-23 上午 12:05');
      expect(Formatters.dateTimeCn('2026-09-23 12:00:00'),
          '2026-09-23 下午 12:00');
      expect(Formatters.dateTimeCn('2026-09-23 13:45:00'),
          '2026-09-23 下午 1:45');
      expect(Formatters.dateTimeCn('2026-09-23 23:59:00'),
          '2026-09-23 下午 11:59');
    });

    test('年/月/日补零到 2 位', () {
      expect(Formatters.dateTimeCn('2026-01-05 09:07:00'),
          '2026-01-05 上午 9:07');
    });

    test('无法解析的字符串原样返回', () {
      expect(Formatters.dateTimeCn('bad'), 'bad');
    });
  });

  group('Formatters.timeOfEpoch', () {
    test('本地时间戳格式化为 HH:mm（补零）', () {
      expect(
        Formatters.timeOfEpoch(
            DateTime(2026, 9, 22, 8, 5).millisecondsSinceEpoch),
        '08:05',
      );
      expect(
        Formatters.timeOfEpoch(DateTime(2026, 1, 1).millisecondsSinceEpoch),
        '00:00',
      );
      expect(
        Formatters.timeOfEpoch(
            DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch),
        '23:59',
      );
    });
  });
}
