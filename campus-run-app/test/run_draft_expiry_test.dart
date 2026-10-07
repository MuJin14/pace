import 'package:campus_run_app/core/storage/run_draft_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 草稿过期判定。
///
/// ## 真实故障
///
/// 用户反馈：「原本应该是个合格的时间，结果开始时间给我定位到昨天了，
/// 导致成绩无效」。
///
/// 原来恢复草稿**只比对运动类型**，不看时间。于是昨天草稿里的轨迹点被并进
/// 今天这条轨迹 —— 数据库里三条被作废的记录都是这个成因
/// （轨迹跨 17.9 小时、点均间隔 1742 秒，中间大段没在记录）。
///
/// 这里守的就是「过期草稿必须被识别出来」这条判据。
void main() {
  const minute = 60 * 1000;
  const hour = 60 * minute;

  /// 用固定基准时刻，避免测试随执行时间漂移。
  const now = 1800000000000;

  RunDraft draftStartedAt(int startedAtMs) => RunDraft(
        type: 1,
        points: [
          {'latitude': 30.0, 'longitude': 120.0, 'timestamp': startedAtMs},
        ],
        elapsedMs: 5 * minute,
        startedAtMs: startedAtMs,
      );

  group('草稿过期判定', () {
    test('刚创建的草稿不过期', () {
      expect(draftStartedAt(now).isExpiredAt(now), isFalse);
    });

    test('一小时前的草稿不过期（跑完忘了结束，回来点结束）', () {
      expect(draftStartedAt(now - hour).isExpiredAt(now), isFalse);
    });

    test('刚好等于上限不过期（判据是「大于」）', () {
      final d = draftStartedAt(now - RunDraft.maxAge.inMilliseconds);
      expect(d.isExpiredAt(now), isFalse);
    });

    test('⚠️ 超过上限一秒即过期', () {
      final d = draftStartedAt(now - RunDraft.maxAge.inMilliseconds - 1);
      expect(
        d.isExpiredAt(now),
        isTrue,
        reason: '过期草稿若被恢复，昨天的轨迹点会并进今天，直接毁掉这次成绩',
      );
    });

    test('⚠️ 昨天的草稿必须过期（用户报的场景）', () {
      final d = draftStartedAt(now - 24 * hour);
      expect(d.isExpiredAt(now), isTrue);
      expect(d.ageAt(now)!.inHours, 24);
    });

    test('上限取 6 小时：够覆盖「晚上回来点结束」，又拦得住跨天', () {
      expect(RunDraft.maxAge, const Duration(hours: 6));
      expect(RunDraft.maxAge.inHours, lessThan(24),
          reason: '上限若 ≥ 24 小时就拦不住「隔天再开跑接上昨天」');
      expect(RunDraft.maxAge.inHours, greaterThanOrEqualTo(2),
          reason: '太小会误删正当的「跑完忘了结束」场景');
    });
  });

  group('边界与健壮性', () {
    test('没有开始时间（0）时不过期 —— 无法判定就不删', () {
      final d = draftStartedAt(0);
      expect(d.ageAt(now), isNull);
      expect(d.isExpiredAt(now), isFalse,
          reason: '无法判定时宁可保留，也不要误删用户的数据');
    });

    test('时钟被改到过去（负年龄）时不过期', () {
      final d = draftStartedAt(now + 2 * hour); // 开始时间在未来
      expect(d.ageAt(now), isNull);
      expect(d.isExpiredAt(now), isFalse);
    });

    test('ageAt 的返回值是精确的毫秒差', () {
      final d = draftStartedAt(now - 90 * minute);
      expect(d.ageAt(now), const Duration(minutes: 90));
    });
  });

  group('序列化', () {
    test('存取往返后过期判定不变', () {
      final src = draftStartedAt(now - 24 * hour);
      final restored = RunDraft.fromJson(src.toJson())!;

      expect(restored.startedAtMs, src.startedAtMs);
      expect(restored.isExpiredAt(now), isTrue,
          reason: '往返丢失开始时间就再也判不出过不过期了');
    });

    test('缺少 startedAtMs 字段时按 0 处理（不过期）', () {
      final r = RunDraft.fromJson({
        'type': 1,
        'points': [
          {'latitude': 30.0, 'longitude': 120.0, 'timestamp': now},
        ],
        'elapsedMs': 1000,
      })!;
      expect(r.startedAtMs, 0);
      expect(r.isExpiredAt(now), isFalse);
    });
  });
}
