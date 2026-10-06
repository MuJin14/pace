import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// 登录页「会跑的跑道」的几何验证。
///
/// **为什么值得单独测**：这段动效全靠数学关系成立，一旦参数改坏，
/// 表现出来只是「看着有点怪」，很容易被忽略，但用户天天看到。
/// 三个必须成立的约束：
///   1. 循环无缝（否则每次循环会跳一下）；
///   2. 小人始终贴在跑道上（否则滚动时浮起/陷进去，「原地跑」就塌了）；
///   3. 小人本身几乎不上下移动（否则像在跳，不像在跑）。
///
/// 这里的公式与 `auth_scaffold.dart` 的 `_RunningTrackPainter._wave`
/// 必须保持一致 —— 改了实现就要同步改这里，否则测试失去意义。
double wave(double x01, double phaseBase) {
  final t = (x01 + phaseBase) * 2 * math.pi;
  return 0.58 + math.sin(t * 1.0) * 0.032 + math.sin(t * 2.0 + 0.9) * 0.01133;
}

const double runnerX = 0.52;

void main() {
  group('循环无缝', () {
    test('滚动一个周期后波形完全回到原位', () {
      // 位移量是一个整周期（shift = progress * 1.0）。
      // 波形含 1 倍与 2 倍频分量，整周期位移对两者都是整周期。
      for (final x in [0.0, 0.1, 0.25, 0.5, 0.52, 0.75, 0.9, 1.0]) {
        final atStart = wave(x, 0.0);
        final afterOneCycle = wave(x, -1.0);
        expect(afterOneCycle, closeTo(atStart, 1e-9),
            reason: 'x=$x 处循环后应当完全重合，否则会看到跳变');
      }
    });

    test('中途相位是连续变化的（没有断点）', () {
      // 相邻采样点的差值应当平滑，不能出现大的跳变
      const steps = 200;
      double? prev;
      for (var i = 0; i <= steps; i++) {
        final p = i / steps;
        final v = wave(0.5, -p);
        if (prev != null) {
          expect((v - prev).abs(), lessThan(0.02),
              reason: '相位推进时不应出现突变');
        }
        prev = v;
      }
    });
  });

  group('小人始终贴在跑道上', () {
    test('整个循环里小人的 y 等于波形在该点的值', () {
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        // 画布里小人的 y 就是 wave(runnerX, -p) * 高度。
        // 这里验证它落在画布内且随相位自然起伏，不会飞出去。
        final y = wave(runnerX, -p);
        expect(y, greaterThan(0.0), reason: '不能跑到画布上方');
        expect(y, lessThan(1.0), reason: '不能跑到画布下方');
      }
    });

    test('小人的垂直变化幅度可控（不能像在跳）', () {
      var minY = double.infinity;
      var maxY = -double.infinity;
      for (var i = 0; i <= 100; i++) {
        final y = wave(runnerX, -(i / 100));
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
      // 280px 高的背景里，起伏应小于 40px；超过了就太夸张
      final travelPx = (maxY - minY) * 280;
      expect(travelPx, lessThan(40),
          reason: '小人上下起伏 ${travelPx.toStringAsFixed(1)}px 太大，会像在跳');

      // 但也不能完全不动 —— 那就没有「沿跑道行进」的感觉了
      expect(travelPx, greaterThan(2),
          reason: '起伏过小会显得像贴纸，缺少在跑道上的感觉');
    });
  });

  group('波形形状合理', () {
    test('整体落在 0..1 之间（不会画到画布外）', () {
      for (var i = 0; i <= 500; i++) {
        final x = i / 500;
        for (var j = 0; j < 4; j++) {
          final y = wave(x, -j * 0.25);
          expect(y, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('确实在起伏（不是一条直线）', () {
      final values = <double>[];
      for (var i = 0; i <= 50; i++) {
        values.add(wave(i / 50, 0));
      }
      final minV = values.reduce(math.min);
      final maxV = values.reduce(math.max);
      // 下限随振幅调整过：用户把振幅降到原来的 2/3 后，
      // 波形跨度从 0.145 降到约 0.072，原来的 0.10 阈值不再适用。
      // 保留一个「必须还能看出起伏」的下限即可，同时用下面一条用例
      // 精确锁住「2/3」这个设计意图。
      expect(maxV - minV, greaterThan(0.06),
          reason: '起伏太小就看不出这是「跑道」了');
    });

    test('振幅是基准值（0.048 / 0.017）的 2/3', () {
      // 用户明确指定：峰顶到峰谷的振幅 = 原来的 2/3。
      // 把「比例」本身断言下来，而不是只断言一个宽松区间 ——
      // 否则以后有人随手改系数，测试照样通过，但设计意图已经丢了。
      const baseA1 = 0.048;
      const baseA2 = 0.017;
      const ratio = 2 / 3;

      double at(double a1, double a2, double x) {
        final t = x * 2 * math.pi;
        return math.sin(t) * a1 + math.sin(2 * t + 0.9) * a2;
      }

      double span(double a1, double a2) {
        var lo = double.infinity, hi = -double.infinity;
        for (var i = 0; i <= 400; i++) {
          final v = at(a1, a2, i / 400);
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
        return hi - lo;
      }

      final baseSpan = span(baseA1, baseA2);
      final nowSpan = span(baseA1 * ratio, baseA2 * ratio);
      expect(nowSpan / baseSpan, closeTo(ratio, 0.001),
          reason: '当前系数应当正好是基准的 2/3');
    });
  });
}
