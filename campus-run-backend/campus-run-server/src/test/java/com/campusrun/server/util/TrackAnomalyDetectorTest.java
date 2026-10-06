package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import com.campusrun.server.util.TrackAnomalyDetector.Anomaly;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

/**
 * 反作弊阈值的行为固化。这些用例的价值在于：阈值被误改（放宽或收紧）时立刻失败，
 * 避免「为了跑通测试而把作弊样本也放过」的隐性回归。
 */
class TrackAnomalyDetectorTest {

    private static final long NOW = 1_800_000_000_000L;

    /** 纬度方向每 0.0001° ≈ 11.1m；用来按目标配速造轨迹。 */
    private static final double METERS_PER_LAT_STEP = 11.1;

    /**
     * 造一条匀速直线轨迹。
     *
     * @param points   点数
     * @param stepMeters 相邻点间距（米）
     * @param secondsPerStep 相邻点间隔（秒）
     */
    private static List<TrackPoint> uniformTrack(int points, double stepMeters, double secondsPerStep) {
        List<TrackPoint> track = new ArrayList<>(points);
        double latStep = stepMeters / METERS_PER_LAT_STEP * 0.0001;
        long t = NOW - (long) (secondsPerStep * 1000 * points);
        for (int i = 0; i < points; i++) {
            track.add(new TrackPoint(39.0 + latStep * i, 116.0, t, 8.0));
            t += (long) (secondsPerStep * 1000);
        }
        return track;
    }

    private static long durationSeconds(List<TrackPoint> track) {
        return (track.get(track.size() - 1).getTimestamp() - track.get(0).getTimestamp()) / 1000;
    }

    private static Anomaly detect(List<TrackPoint> track, int type) {
        double distance = GpsUtil.totalDistanceMeters(track);
        return TrackAnomalyDetector.detect(
                track, type, distance, durationSeconds(track),
                track.get(0).getTimestamp(), NOW);
    }

    @Test
    @DisplayName("正常跑步轨迹（约 8 km/h）不判无效")
    void normalRun_isValid() {
        // 8 km/h = 2.22 m/s；每 5 秒约 11.1 米
        List<TrackPoint> track = uniformTrack(40, 11.1, 5);
        assertNull(detect(track, 1));
    }

    @Test
    @DisplayName("正常骑行轨迹（约 25 km/h）不判无效")
    void normalCycling_isValid() {
        // 25 km/h = 6.94 m/s；每 5 秒约 34.7 米
        List<TrackPoint> track = uniformTrack(40, 34.7, 5);
        assertNull(detect(track, 2));
    }

    @Test
    @DisplayName("跑步冲刺（约 25 km/h 短程）仍不判无效，阈值留了余量")
    void fastSprintRun_isValid() {
        // 25 km/h = 6.94 m/s，低于跑步段上限 45 km/h 与全程上限 30 km/h
        List<TrackPoint> track = uniformTrack(20, 34.7, 5);
        assertNull(detect(track, 1));
    }

    @Test
    @DisplayName("点数不足 2 判无效")
    void tooFewPoints() {
        assertEquals(Anomaly.POINTS_TOO_FEW,
                TrackAnomalyDetector.detect(List.of(new TrackPoint(39.0, 116.0, NOW, 8.0)),
                        1, 0, 0, NOW, NOW));
        assertEquals(Anomaly.POINTS_TOO_FEW,
                TrackAnomalyDetector.detect(null, 1, 0, 10, NOW, NOW));
    }

    @Test
    @DisplayName("时长为 0 判无效")
    void nonPositiveDuration() {
        List<TrackPoint> track = uniformTrack(5, 11.1, 5);
        assertEquals(Anomaly.NON_POSITIVE_DURATION,
                TrackAnomalyDetector.detect(track, 1, 44.4, 0, track.get(0).getTimestamp(), NOW));
    }

    @Test
    @DisplayName("开始时间远超服务器当前时间判无效（伪造未来时间）")
    void futureStartTime() {
        List<TrackPoint> track = uniformTrack(10, 11.1, 5);
        assertEquals(Anomaly.FUTURE_START_TIME,
                TrackAnomalyDetector.detect(track, 1, 100, 50,
                        NOW + 10 * 60 * 1000L, NOW));
    }

    @Test
    @DisplayName("GPS 瞬移（3 秒移动 1 公里）判瞬时速度超限")
    void teleportSegment() {
        // 0.009° 纬度 ≈ 1km，仅 3 秒 → 1200 km/h
        List<TrackPoint> track = List.of(
                new TrackPoint(39.0, 116.0, NOW - 3000, 8.0),
                new TrackPoint(39.009, 116.0, NOW, 8.0));
        assertEquals(Anomaly.SEGMENT_SPEED_TOO_HIGH, detect(track, 1));
    }

    /**
     * 回归：**正常跑步/骑行不能因为 GPS 采样间隔短而被判作弊**。
     *
     * <p>原实现用 `段速度 ÷ 段时长` 当加速度，这在物理上不成立：
     * 跑步 3 m/s、间隔 0.3 秒就会算出 10 m/s²，撞上 8 m/s² 的阈值，
     * 于是**一次完全正常的跑步被整单作废、不计排行榜**。
     * 骑行速度更高，几乎必然命中。这里把「短间隔的正常轨迹应放行」固化下来。
     */
    @Test
    @DisplayName("短采样间隔的正常轨迹不应被判加速度异常（回归：曾把正常跑步整单作废）")
    void shortSamplingIntervalIsNotAccelerationAnomaly() {
        // 跑步 3 m/s，每 0.3 秒一个点（约 0.9 米）—— 旧实现会算出 10 m/s²
        assertNull(detect(uniformTrack(60, 0.9, 0.3), 1),
                "跑步 3 m/s、0.3s 采样是正常 GPS 行为，不能判作弊");

        // 骑行 8 m/s（≈29 km/h），每 0.2 秒一个点（约 1.6 米）—— 旧实现会算出 40 m/s²
        assertNull(detect(uniformTrack(60, 1.6, 0.2), 2),
                "骑行 29 km/h、0.2s 采样是常见的记录频率，不能判作弊");

        // 更密集：每 0.1 秒
        assertNull(detect(uniformTrack(60, 0.5, 0.1), 1),
                "0.1s 采样间隔很常见，不应因此判作弊");
    }

    /**
     * 严重超速仍必须抓（这是抓 GPS 瞬移的主力判定）。
     *
     * <p>说明：修好加速度公式后，「定长采样下的瞬间位移」主要由
     * {@code SEGMENT_SPEED_TOO_HIGH} 抓 —— 它更直接也更稳。
     * 加速度判定只在**采样间隔不规则**时起作用（见常量注释）。
     * 所以这里断言的是速度判定兜住了作弊场景，而不是硬凑一个加速度 fixture。
     */
    @Test
    @DisplayName("作弊式瞬移仍会被抓（由段速度判定兜住）")
    void teleportStillCaughtBySegmentSpeed() {
        // 1 秒内移动 30 米 = 108 km/h，远超跑步 45 km/h 上限
        List<TrackPoint> track = List.of(
                new TrackPoint(39.0, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.00027, 116.0, NOW - 1000, 8.0),
                new TrackPoint(39.00270, 116.0, NOW, 8.0));
        assertEquals(Anomaly.SEGMENT_SPEED_TOO_HIGH, detect(track, 1));
    }

    @Test
    @DisplayName("时间未前进但位置大幅移动判无效；小幅抖动放行")
    void duplicateTimestamp() {
        // 真作弊特征：时间戳完全没变，位置却跳了 ~20 米（真人做不到）。
        // 阈值从 1m 提到 5m 的原因：静止时 GPS 抖动 2-3 米是常态，
        // 原先 1m 的阈值会把「站着不动」的正常用户判成作弊。
        List<TrackPoint> teleport = List.of(
                new TrackPoint(39.0, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.0002, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.0004, 116.0, NOW - 1000, 8.0));
        assertEquals(Anomaly.DUPLICATE_TIMESTAMP_WITH_MOVE, detect(teleport, 1));

        // 静止抖动（≈2.2m）在时间相同时应放行 —— 这是正常 GPS 行为，不是作弊
        List<TrackPoint> jitter = List.of(
                new TrackPoint(39.0, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.00002, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.00004, 116.0, NOW - 1000, 8.0));
        assertNull(detect(jitter, 1), "小幅抖动不应被判作弊");

        // 更小的抖动同样放行
        List<TrackPoint> tinyJitter = List.of(
                new TrackPoint(39.0, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.000001, 116.0, NOW - 2000, 8.0),
                new TrackPoint(39.000001, 116.0, NOW - 1000, 8.0));
        assertNull(detect(tinyJitter, 1));

        // 精度过差的点不参与判定：即使它带有「时间未前进却大幅位移」的作弊特征
        // （单看那一段会被判 DUPLICATE_TIMESTAMP_WITH_MOVE），
        // 也不应据此把整次运动作废 —— 那是真实存在的高楼/树荫漂移。
        // 这条同时验证了「精度判断发生在重复时间戳判断之前」。
        // 时间间隔统一为 20 秒，避免触发平均速度等其他判定干扰断言。
        List<TrackPoint> poorAccuracy = List.of(
                new TrackPoint(39.0, 116.0, NOW - 80000, 8.0),
                new TrackPoint(39.0001, 116.0, NOW - 60000, 8.0),
                new TrackPoint(39.0020, 116.0, NOW - 60000, 80.0),
                new TrackPoint(39.0002, 116.0, NOW - 40000, 8.0),
                new TrackPoint(39.0003, 116.0, NOW - 20000, 8.0));
        assertNull(detect(poorAccuracy, 1), "精度过差的点应被忽略，不能据此判作弊");
    }

    @Test
    @DisplayName("全程平均速度超限判无效（伪造 100km / 60 秒）")
    void avgSpeedTooHigh() {
        // 直接用「总距离 + 时长」判定，无需构造真实 100km 轨迹
        List<TrackPoint> track = uniformTrack(10, 11.1, 5);
        assertEquals(Anomaly.AVG_SPEED_TOO_HIGH,
                TrackAnomalyDetector.detect(track, 1, 100_000, 60,
                        track.get(0).getTimestamp(), NOW));
    }

    @Test
    @DisplayName("骑行阈值比跑步宽松：60 km/h 的骑行不算超限，同样的跑步算超限")
    void cyclingThresholdIsLooser() {
        List<TrackPoint> track = uniformTrack(10, 11.1, 5);
        long start = track.get(0).getTimestamp();
        // 20 km/h：骑行与跑步都放行
        assertNull(TrackAnomalyDetector.detect(track, 2, 20_000, 3600, start, NOW));
        // 45 km/h：骑行放行（<60），跑步超限（>30）
        assertEquals(Anomaly.AVG_SPEED_TOO_HIGH,
                TrackAnomalyDetector.detect(track, 1, 45_000, 3600, start, NOW));
    }

    @Test
    @DisplayName("原地漂移攒距离判无效（30 分钟只挪了 100 米不到）")
    void stationaryDrift() {
        // 距离 400m（触发漂移检查门槛 300m）、时长 1800s → 0.22 m/s < 0.83
        List<TrackPoint> track = uniformTrack(10, 11.1, 5);
        assertEquals(Anomaly.STATIONARY_DRIFT,
                TrackAnomalyDetector.detect(track, 1, 400, 1800,
                        track.get(0).getTimestamp(), NOW));
    }

    @Test
    @DisplayName("不足漂移检查门槛的短距离慢速不判无效（避免误伤慢走/热身）")
    void shortSlowWalk_isValid() {
        List<TrackPoint> track = uniformTrack(10, 11.1, 5);
        long start = track.get(0).getTimestamp();
        // 200m / 600s → 0.33 m/s，低于阈值但距离 < 300m，不检查
        assertNull(TrackAnomalyDetector.detect(track, 1, 200, 600, start, NOW));
    }
}
