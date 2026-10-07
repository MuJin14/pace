package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 开始时间校正的测试。
 *
 * <h2>真实故障</h2>
 *
 * 用户反馈：「我刚刚跑了一下，原本应该是个合格的时间，结果开始时间给我定位到昨天了，
 * 导致成绩无效」。
 *
 * <p>链路：上一次运动没上传成功 → 本地草稿留着那时的 startedAt →
 * 今天再开跑时草稿被恢复、`_startedAt` 变成昨天 → 轨迹点时间戳却是今天的 →
 * 服务端 {@code duration = endTime - startTime} ≈ 86400 秒 →
 * 平均速度趋近 0 → 命中 STATIONARY_DRIFT「疑似原地漂移」→ **成绩作废**。
 *
 * <p>修法：轨迹点的时间戳比客户端上报的开始时间可信，差得离谱时以轨迹为准。
 * 这组测试就是这个判定的护栏 —— 它一旦出错，后果是「用户的成绩被静默作废」
 * 或「时长虚高」，两种都极难排查。
 */
class StartTimeCorrectionTest {

    private static final long NOW = 1_800_000_000_000L; // 任意基准时刻

    private TrackPoint point(long tsMillis) {
        TrackPoint p = new TrackPoint();
        p.setLatitude(30.0);
        p.setLongitude(120.0);
        p.setTimestamp(tsMillis);
        return p;
    }

    private List<TrackPoint> trackAt(long firstMs) {
        List<TrackPoint> t = new ArrayList<>();
        t.add(point(firstMs));
        t.add(point(firstMs + 1000));
        t.add(point(firstMs + 2000));
        return t;
    }

    // ── 核心：用户报的那个场景 ──────────────────────────────

    @Test
    void staleStartFromYesterday_isReplacedByFirstPoint() {
        // 开始时间 = 昨天（草稿带来的陈旧值），轨迹是今天的
        long yesterday = NOW - 24 * 3600_000L;
        List<TrackPoint> track = trackAt(NOW);

        long effective = TrackAnomalyDetector.effectiveStartTimeMillis(track, yesterday);

        assertEquals(NOW, effective,
                "陈旧的开始时间必须被轨迹首点取代，否则时长会算成约一天，成绩被判无效");
    }

    @Test
    void staleStart_doesNotMakeDurationAbsurd() {
        // 直接验证「修完之后时长是合理的」—— 这才是用户真正在意的结果
        long yesterday = NOW - 24 * 3600_000L;
        long endMs = NOW + 20 * 60_000L; // 跑了 20 分钟
        List<TrackPoint> track = trackAt(NOW);

        long effective = TrackAnomalyDetector.effectiveStartTimeMillis(track, yesterday);
        long durationSeconds = (endMs - effective) / 1000;

        assertTrue(durationSeconds >= 20 * 60 - 2 && durationSeconds <= 20 * 60 + 2,
                "校正后时长应约等于真实的 20 分钟，实际 " + durationSeconds + " 秒");
    }

    // ── 正常情况不能被改动 ──────────────────────────────────

    @Test
    void normalFewSecondsGap_isKept() {
        // 「点开 App → 等定位」的几秒是真实间隔，用户认可这段时间，要保留
        long reported = NOW - 30_000L; // 首次定位花了 30 秒
        List<TrackPoint> track = trackAt(NOW);

        assertEquals(reported,
                TrackAnomalyDetector.effectiveStartTimeMillis(track, reported),
                "几十秒的搜索卫星时间属于正常，不该被改写");
    }

    @Test
    void gapExactlyAtThreshold_isKept() {
        long reported = NOW - TrackAnomalyDetector.MAX_START_TIME_GAP_SECONDS * 1000L;
        List<TrackPoint> track = trackAt(NOW);

        assertEquals(reported,
                TrackAnomalyDetector.effectiveStartTimeMillis(track, reported),
                "刚好等于阈值应当保留（阈值判据是「大于」）");
    }

    @Test
    void gapJustOverThreshold_isReplaced() {
        long reported = NOW - (TrackAnomalyDetector.MAX_START_TIME_GAP_SECONDS + 1) * 1000L;
        List<TrackPoint> track = trackAt(NOW);

        assertEquals(NOW,
                TrackAnomalyDetector.effectiveStartTimeMillis(track, reported),
                "超过阈值一秒就该判为陈旧值");
    }

    @Test
    void startLaterThanFirstPoint_isClampedToFirstPoint() {
        // 上报的开始时间晚于第一个点：时长会被压缩、配速虚高，一律以首点为准
        long reported = NOW + 5_000L;
        List<TrackPoint> track = trackAt(NOW);

        assertEquals(NOW,
                TrackAnomalyDetector.effectiveStartTimeMillis(track, reported),
                "开始时间不能晚于第一次记录到的时间");
    }

    // ── 边界与健壮性 ────────────────────────────────────────

    @Test
    void emptyOrNullTrack_returnsReported() {
        long reported = NOW - 100_000L;
        assertEquals(reported,
                TrackAnomalyDetector.effectiveStartTimeMillis(null, reported));
        assertEquals(reported,
                TrackAnomalyDetector.effectiveStartTimeMillis(new ArrayList<>(), reported),
                "没有轨迹可依据时只能原样返回，不能凭空造一个时间");
    }

    @Test
    void trackWithoutTimestamps_returnsReported() {
        List<TrackPoint> t = new ArrayList<>();
        TrackPoint p = new TrackPoint();
        p.setLatitude(30.0);
        p.setLongitude(120.0);
        // timestamp 故意留空
        t.add(p);
        t.add(p);

        long reported = NOW - 999_000L;
        assertEquals(reported,
                TrackAnomalyDetector.effectiveStartTimeMillis(t, reported));
    }

    @Test
    void firstTimestampedPointWins_whenLeadingPointsHaveNoTime() {
        List<TrackPoint> t = new ArrayList<>();
        TrackPoint noTime = new TrackPoint();
        noTime.setLatitude(30.0);
        noTime.setLongitude(120.0);
        t.add(noTime);
        t.add(point(NOW));

        long reported = NOW - 24 * 3600_000L;
        assertEquals(NOW,
                TrackAnomalyDetector.effectiveStartTimeMillis(t, reported),
                "应跳过没有时间戳的点，找到第一个有时间的时间戳");
    }

    @Test
    void nullElementsInTrack_doNotThrow() {
        List<TrackPoint> t = new ArrayList<>();
        t.add(null);
        t.add(point(NOW));

        long reported = NOW - 24 * 3600_000L;
        assertEquals(NOW, TrackAnomalyDetector.effectiveStartTimeMillis(t, reported),
                "轨迹里有 null 元素时不能崩");
    }
}
