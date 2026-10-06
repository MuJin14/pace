import 'package:campus_run_app/core/storage/run_draft_storage.dart';
import 'package:campus_run_app/data/models/track_point.dart';
import 'package:campus_run_app/features/activity/utils/track_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 跑步核心链路的单元测试。
///
/// 这些用例保护的是 App 唯一不可替代的东西：**一次真实的跑步记录**。
/// 采样规则写错的后果是距离虚高数倍（用户觉得"定位不准"）、
/// 距离恒为 0（用户白跑一次）、或正常跑步被判作弊整单作废；
/// 草稿存错的后果是整次运动丢失。
void main() {
  const sampler = TrackSampler();
  const metersPerLatDegree = 111_320.0;

  /// 生成一条按固定速度、固定采样间隔前进的轨迹（沿纬度方向）。
  List<TrackPoint> walk(double metersPerSecond, int intervalMs, int seconds) {
    final steps = seconds * 1000 ~/ intervalMs;
    return [
      for (var i = 0; i <= steps; i++)
        TrackPoint(
          latitude: 39.0 + (metersPerSecond * intervalMs / 1000.0 * i) / metersPerLatDegree,
          longitude: 116.0,
          timestamp: i * intervalMs,
          accuracy: 8,
        ),
    ];
  }

  /// 确定性伪随机（LCG）：测试必须可复现，不能用 Random() 不带种子。
  double nextUnit(List<int> seed) {
    seed[0] = (seed[0] * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed[0] / 0x7FFFFFFF; // [0, 1)
  }

  /// 生成「站在原地」的 GPS 抖动：在真实位置附近做随机游走。
  ///
  /// 用随机游走而不是完美的两点交替 —— 真实 GPS 噪声没有周期性，
  /// 完美交替会让 5 秒窗口里「净位移 1 米 / 路径 2 米」显得"有方向性"，
  /// 那是测试造出来的假象，不是算法的真实行为。
  List<TrackPoint> stationaryJitter(int seconds, {double amplitudeMeters = 1.0}) {
    final seed = <int>[20261004];
    final points = <TrackPoint>[];
    var lat = 39.0;
    var lng = 116.0;
    for (var i = 0; i <= seconds; i++) {
      points.add(TrackPoint(
        latitude: lat,
        longitude: lng,
        timestamp: i * 1000,
        accuracy: 5,
      ));
      // 每步随机游走，并做轻微的回归（真实抖动会围绕真实位置聚拢）
      lat += (nextUnit(seed) - 0.5) * 2 * amplitudeMeters / metersPerLatDegree;
      lng += (nextUnit(seed) - 0.5) * 2 * amplitudeMeters / metersPerLatDegree;
      lat += (39.0 - lat) * 0.05;
      lng += (116.0 - lng) * 0.05;
    }
    return points;
  }

  /// 相邻点原始累加（不做任何过滤）—— 用于对比"假距离"有多大。
  double rawSum(TrackSampler s, List<TrackPoint> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += s.chord(points[i - 1], points[i]);
    }
    return total;
  }

  group('TrackSampler 精度过滤', () {
    test('精度差的点不被采信（这是"定位不准"最常见的原因）', () {
      expect(sampler.isAccuracyAcceptable(60.0), isFalse,
          reason: '误差 60m > 阈值 30m，不参与距离累加');
    });

    test('精度好（或缺失）的点被采信', () {
      expect(sampler.isAccuracyAcceptable(8.0), isTrue);
      // 老数据没有 accuracy 字段时不做判断
      expect(sampler.isAccuracyAcceptable(null), isTrue);
    });

    test('整条轨迹全是脏点时距离为 0', () {
      final points = walk(1.4, 1000, 30)
          .map((p) => TrackPoint(
                latitude: p.latitude,
                longitude: p.longitude,
                timestamp: p.timestamp,
                accuracy: 80,
              ))
          .toList();
      expect(sampler.totalDistance(points), 0.0);
    });
  });

  // ⚠️ 这一组是「运动记录距离为 0」的回归，是全套测试里最重要的一组。
  //
  // 旧实现的判据是「位移 < 2 米 且 间隔 < 5 秒 → 丢弃」。
  // geolocator 在多数机型上是 1 秒采样，于是慢走时
  // 每段 1.4 米 < 2 米、间隔 1 秒 < 5 秒 —— 两支都命中，
  // **每一段都被丢弃，距离恰好为 0**。
  // 线上表现是「走路的人全为 0，跑步的人全部正常」，
  // 所以看起来像「部分账号有问题」，实际与账号无关。
  group('慢走/短间隔不能算出 0（线上 bug 回归）', () {
    test('慢走 1.4m/s、1 秒采样：必须有距离', () {
      final d = sampler.totalDistance(walk(1.4, 1000, 120));
      expect(d, greaterThan(120),
          reason: '慢走 120 秒约 168 米，实际算出 $d 米。返回 0 就是线上那个 bug');
    });

    test('慢跑 2.0m/s、1 秒采样：必须有距离（旧实现严格小于 2 米会丢）', () {
      final d = sampler.totalDistance(walk(2.0, 1000, 120));
      expect(d, greaterThan(180), reason: '实际算出 $d 米');
    });

    // 0.6 m/s 是算法对「行走」的灵敏度下限：更慢时 5 秒窗口的
    // 净位移与路径长度接近（无方向性），会被当成原地漂移。
    // 这符合设计取舍 —— 比散步还慢的情况请用「暂停」。
    test('慢走下限 0.6m/s：所有采样间隔都要有准确距离', () {
      for (final interval in [1000, 2000, 3000, 5000]) {
        final d = sampler.totalDistance(walk(0.6, interval, 120));
        expect(d, greaterThan(50),
            reason: '$interval ms 采样下算出 $d 米，期望约 72 米');
      }
    });

    test('跑步 3.0m/s：本来就正常，修复后必须依然正常', () {
      final d = sampler.totalDistance(walk(3.0, 1000, 120));
      expect(d, greaterThan(300), reason: '实际算出 $d 米');
    });

    test('采样间隔 1s 与 5s 不应得出「一个有距离、一个是 0」这种相反结论', () {
      final d1 = sampler.totalDistance(walk(1.4, 1000, 120));
      final d5 = sampler.totalDistance(walk(1.4, 5000, 120));
      expect(d1, greaterThan(0), reason: '1 秒采样不能为 0');
      expect(d5, greaterThan(0), reason: '5 秒采样不能为 0');
      expect((d1 - d5).abs() / d5, lessThan(0.3),
          reason: '1 秒采样 $d1 米、5 秒采样 $d5 米，不应相差三成以上');
    });
  });

  group('TrackSampler 抖动过滤', () {
    test('静止随机抖动：距离应远小于原始累加（不靠"处处丢弃"来为 0）', () {
      final points = stationaryJitter(120, amplitudeMeters: 1.5);

      final raw = rawSum(sampler, points);
      final filtered = sampler.totalDistance(points);

      expect(raw, greaterThan(50), reason: '原始累加应该有可观的假距离，实际 $raw 米');
      expect(filtered, lessThan(raw * 0.5),
          reason: '过滤后应显著小于原始累加，实际 filtered=$filtered raw=$raw');
    });

    test('走了几十米后停下不动：停下来之后距离不应继续明显增长', () {
      final moving = walk(1.4, 1000, 60); // 走 60 秒 ≈ 84 米
      final lastTs = moving.last.timestamp;
      final lastLat = moving.last.latitude;

      // 停下后 120 秒的原地抖动（围绕停下的位置）
      final seed = <int>[777];
      final stationary = <TrackPoint>[];
      var lat = lastLat;
      for (var i = 1; i <= 120; i++) {
        stationary.add(TrackPoint(
          latitude: lat,
          longitude: 116.0,
          timestamp: lastTs + i * 1000,
          accuracy: 5,
        ));
        lat += (nextUnit(seed) - 0.5) * 3.0 / metersPerLatDegree;
        lat += (lastLat - lat) * 0.15;
      }

      final afterWalk = sampler.totalDistance(moving);
      final withStop = sampler.totalDistance([...moving, ...stationary]);

      expect(afterWalk, greaterThan(60), reason: '真实走的距离必须算进去，实际 $afterWalk 米');
      expect(withStop - afterWalk, lessThan(25),
          reason: '停下 120 秒不应再涨 25 米以上，实际涨了 ${withStop - afterWalk} 米');
    });
  });

  group('TrackSampler 正常场景', () {
    test('正常跑步距离计算准确（0.001° 纬度 ≈ 111 米）', () {
      final points = <TrackPoint>[
        for (var i = 0; i < 5; i++)
          TrackPoint(
            latitude: 39.0 + i * 0.001,
            longitude: 116.0,
            timestamp: i * 30000,
            accuracy: 8,
          ),
      ];
      expect(sampler.totalDistance(points), closeTo(444, 25));
    });

    test('空轨迹与单点轨迹返回 0', () {
      expect(sampler.totalDistance(const []), 0.0);
      expect(
        sampler.totalDistance(const [
          TrackPoint(latitude: 39.0, longitude: 116.0, timestamp: 0, accuracy: 5),
        ]),
        0.0,
      );
    });
  });

  group('TrackDistanceAccumulator（录制路径用的增量接口）', () {
    test('逐点累加的结果与整条重算一致', () {
      final points = walk(1.4, 1000, 60);
      final acc = TrackDistanceAccumulator(sampler);
      for (final p in points) {
        acc.add(p);
      }
      expect(acc.distance, closeTo(sampler.totalDistance(points), 0.001),
          reason: '录制时用增量、恢复时用重算，两条路径必须给出同一个数');
    });

    test('距离单调不减（界面上不能让数字往回跳）', () {
      final acc = TrackDistanceAccumulator(sampler);
      var prev = 0.0;
      for (final p in walk(1.4, 1000, 60)) {
        final now = acc.add(p);
        expect(now, greaterThanOrEqualTo(prev - 0.001),
            reason: '累计距离回退会让用户以为丢数据');
        prev = now;
      }
    });

    test('慢走 0.6m/s 的增量累加也不能为 0', () {
      final acc = TrackDistanceAccumulator(sampler);
      for (final p in walk(0.6, 1000, 120)) {
        acc.add(p);
      }
      expect(acc.distance, greaterThan(50), reason: '实际 ${acc.distance} 米');
    });
  });

  group('RunDraftStorage 序列化与恢复', () {
    test('草稿写入后可读回（轨迹/用时/开始时间都不丢）', () async {
      final storage = InMemoryRunDraftStorage();
      final draft = RunDraft(
        type: 1,
        points: const [
          {'latitude': 39.0, 'longitude': 116.0, 'timestamp': 1000, 'accuracy': 8.0},
          {'latitude': 39.001, 'longitude': 116.0, 'timestamp': 31000, 'accuracy': 8.0},
        ],
        elapsedMs: 30000,
        startedAtMs: 1000,
      );

      await storage.write(draft);
      final restored = await storage.read();

      expect(restored, isNotNull);
      expect(restored!.type, 1);
      expect(restored.points.length, 2);
      expect(restored.elapsedMs, 30000);
      expect(restored.startedAtMs, 1000);
      expect(restored.isEmpty, isFalse);
    });

    test('JSON 往返不丢字段（草稿是跨进程恢复的唯一依据）', () {
      final draft = RunDraft(
        type: 2,
        points: const [
          {'latitude': 39.5, 'longitude': 116.5, 'timestamp': 42, 'accuracy': null},
        ],
        elapsedMs: 1234,
        startedAtMs: 42,
      );

      final back = RunDraft.fromJson(draft.toJson());

      expect(back, isNotNull);
      expect(back!.type, 2);
      expect(back.elapsedMs, 1234);
      expect(back.points.single['latitude'], 39.5);
      expect(back.points.single['timestamp'], 42);
    });

    test('损坏的草稿返回 null 而不是抛异常（否则跑步页会打不开）', () {
      expect(RunDraft.fromJson(const {}), isNull);
      expect(RunDraft.fromJson(const {'points': 'not-a-list'}), isNull);
    });

    test('clear 之后读不到草稿（上传成功必须清理，否则会重复恢复）', () async {
      final storage = InMemoryRunDraftStorage();
      await storage.write(const RunDraft(
        type: 1,
        points: [],
        elapsedMs: 0,
        startedAtMs: 0,
      ));
      expect(await storage.read(), isNotNull);

      await storage.clear();
      expect(await storage.read(), isNull);
    });
  });
}
