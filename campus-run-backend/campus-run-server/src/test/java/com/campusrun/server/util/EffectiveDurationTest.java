package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 时长判定的测试。
 *
 * <h2>真实故障</h2>
 *
 * 用户反馈一次正常跑步被判无效：上报时长 17.9 小时，实际只跑了十几分钟，
 * 平均速度被算成 0，命中「疑似原地漂移」。
 *
 * <p>成因是客户端续接本地草稿继续跑：计时是累计的（一段段跑出来的），
 * 而「结束 − 开始」把中间没在跑的空档也算了进去。
 *
 * <p>修法：让客户端把它计时器上的数字直接上报，服务端优先采用 ——
 * 但**必须不超过轨迹的时间跨度**（时长不可能长于轨迹本身）。
 */
class EffectiveDurationTest {

    private TrackPoint point(long tsMillis) {
        TrackPoint p = new TrackPoint();
        p.setLatitude(30.0);
        p.setLongitude(120.0);
        p.setTimestamp(tsMillis);
        return p;
    }

    /** 造一条跨度为 spanSeconds 的轨迹。 */
    private List<TrackPoint> trackSpanning(long spanSeconds) {
        long base = 1_800_000_000_000L;
        List<TrackPoint> t = new ArrayList<>();
        t.add(point(base));
        t.add(point(base + spanSeconds * 1000 / 2));
        t.add(point(base + spanSeconds * 1000));
        return t;
    }

    // ── 用户报的那个场景 ────────────────────────────────────

    @Test
    void reportedDurationWins_whenTimelineIsInflated() {
        // 真实运动 900 秒（15 分钟），但时间戳相减得到 64457 秒（含空档）
        long timeline = 64457L;
        long span = 64441L;   // 轨迹本身也跨了这么久（续接导致）
        Integer reported = 900;

        long effective = TrackAnomalyDetector.effectiveDurationSeconds(
                reported, timeline, span);

        assertEquals(900, effective,
                "客户端计时器上的数字才是用户看到的时长，必须优先采用");
    }

    @Test
    void reportedDuration_producesReasonableSpeed() {
        // 573 米 / 900 秒 ≈ 2.3 km/h —— 合理；若用 64457 秒则是 0.03 km/h，会被判漂移
        double distanceMeters = 573;
        long effective = TrackAnomalyDetector.effectiveDurationSeconds(900, 64457L, 64441L);
        double kmh = (distanceMeters / 1000.0) / (effective / 3600.0);

        assertTrue(kmh > 1.0,
                "校正后平均速度应回到合理区间，实际 " + kmh + " km/h");
    }

    // ── 约束：不能无条件采信客户端 ──────────────────────────

    @Test
    void absurdReportedDuration_isRejected() {
        // 客户端报了一个比轨迹跨度还长的时长 —— 不可能，退回时间戳相减
        long effective = TrackAnomalyDetector.effectiveDurationSeconds(
                999_999, 600L, 500L);

        assertEquals(600L, effective,
                "时长不可能长于轨迹本身，超出即视为不可信");
    }

    @Test
    void missingReportedDuration_fallsBackToTimeline() {
        assertEquals(600L, TrackAnomalyDetector.effectiveDurationSeconds(null, 600L, 5000L),
                "老版本客户端不传这个字段，必须能继续工作");
    }

    @Test
    void zeroOrNegativeReportedDuration_fallsBack() {
        assertEquals(600L, TrackAnomalyDetector.effectiveDurationSeconds(0, 600L, 5000L));
        assertEquals(600L, TrackAnomalyDetector.effectiveDurationSeconds(-5, 600L, 5000L));
    }

    @Test
    void unknownSpan_fallsBackToTimeline() {
        // 轨迹点太少/没有时间戳 → 无法校验上报值 → 以时间戳相减为准
        assertEquals(600L, TrackAnomalyDetector.effectiveDurationSeconds(900, 600L, 0));
    }

    @Test
    void resultIsAlwaysPositive() {
        // 任何输入都不能返回 0 或负数 —— 那会让平均速度变成 Infinity/NaN
        assertTrue(TrackAnomalyDetector.effectiveDurationSeconds(null, 0L, 0L) > 0);
        assertTrue(TrackAnomalyDetector.effectiveDurationSeconds(0, -100L, 0L) > 0);
        assertTrue(TrackAnomalyDetector.effectiveDurationSeconds(5, 0L, 0L) > 0);
    }

    // ── 轨迹跨度 ────────────────────────────────────────────

    @Test
    void trackSpan_isLastMinusFirst() {
        assertEquals(120L, TrackAnomalyDetector.trackSpanSeconds(trackSpanning(120)));
    }

    @Test
    void trackSpan_handlesDegenerateInput() {
        assertEquals(0L, TrackAnomalyDetector.trackSpanSeconds(null));
        assertEquals(0L, TrackAnomalyDetector.trackSpanSeconds(new ArrayList<>()));

        List<TrackPoint> one = new ArrayList<>();
        one.add(point(1000L));
        assertEquals(0L, TrackAnomalyDetector.trackSpanSeconds(one),
                "只有一个点时无法构成跨度");

        List<TrackPoint> sameTs = new ArrayList<>();
        sameTs.add(point(1000L));
        sameTs.add(point(1000L));
        assertEquals(0L, TrackAnomalyDetector.trackSpanSeconds(sameTs));
    }

    @Test
    void trackSpan_skipsPointsWithoutTimestamp() {
        List<TrackPoint> t = new ArrayList<>();
        TrackPoint noTs = new TrackPoint();
        noTs.setLatitude(30.0);
        noTs.setLongitude(120.0);
        t.add(noTs);
        t.add(point(1_000_000L));
        t.add(point(1_060_000L));

        assertEquals(60L, TrackAnomalyDetector.trackSpanSeconds(t));
    }
}
