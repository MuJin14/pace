package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 「运动记录距离为 0」的根因复现与回归。
 *
 * <p>线上现象：部分账号的运动记录距离显示 0。
 *
 * <p><b>根因</b>：{@code shouldCountSegment} 原来的规则是
 * 「位移 &lt; 2 米 <b>且</b> 间隔 &lt; 5 秒 → 丢弃」。
 * geolocator 在多数机型上是 <b>1 秒采样</b>，于是：
 * <ul>
 *   <li>慢走 1.4 m/s × 1 秒 = 1.40 米 → 两个条件都命中 → 丢弃</li>
 *   <li>慢跑 2.0 m/s × 1 秒 = 2.00 米 → 严格小于 2 也算丢弃</li>
 *   <li>跑步 3.0 m/s × 1 秒 = 3.00 米 → 通过</li>
 * </ul>
 * <b>每一段都被丢弃 → 距离累加恰好为 0</b>。
 * 这解释了「为什么只有部分账号为 0」：取决于<b>速度</b>与<b>采样间隔</b>，
 * 与账号无关 —— 走路的人全为 0，跑步的人全部正常。
 *
 * <p><b>修复</b>：判据改为「位移 ≥ 1 米 <b>或</b> 等效速度 ≥ 0.5 m/s」，
 * 并把累加基准改为<b>相邻已采信点</b>（原来与「上一个被采信点」比较，
 * 连续拒绝时会冻结基准）。
 */
class GpsUtilSlowWalkTest {

    /** 生成一条按固定速度、固定采样间隔行走的轨迹。 */
    private static List<TrackPoint> walk(double metersPerSecond, int intervalMs, int seconds,
                                         double accuracy) {
        List<TrackPoint> track = new ArrayList<>();
        long t0 = 1_700_000_000_000L;
        // 从北京某点开始，沿纬度方向走（1 度纬度 ≈ 111_320 米）
        double lat = 39.9042;
        double metersPerLatDegree = 111_320.0;
        int steps = seconds * 1000 / intervalMs;
        for (int i = 0; i <= steps; i++) {
            TrackPoint p = new TrackPoint();
            p.setLatitude(lat);
            p.setLongitude(116.4074);
            p.setAccuracy(accuracy);
            p.setTimestamp(t0 + (long) i * intervalMs);
            track.add(p);
            lat += (metersPerSecond * intervalMs / 1000.0) / metersPerLatDegree;
        }
        return track;
    }

    @Test
    @DisplayName("慢走 1.4m/s、1 秒采样：距离不能为 0（线上为 0 的那个 bug）")
    void slowWalkWithOneSecondSamplingIsNotZero() {
        List<TrackPoint> track = walk(1.4, 1000, 120, 10.0);

        double distance = GpsUtil.totalDistanceMetersFiltered(track);

        assertTrue(distance > 120,
                "慢走 120 秒约 168 米，实际算出 " + distance
                        + " 米。返回 0 就是线上「运动记录为 0」的根因");
    }

    @Test
    @DisplayName("慢走 1.4m/s、2 秒采样：同样不能为 0")
    void slowWalkWithTwoSecondSamplingIsNotZero() {
        List<TrackPoint> track = walk(1.4, 2000, 120, 10.0);

        double distance = GpsUtil.totalDistanceMetersFiltered(track);

        assertTrue(distance > 120, "2 秒采样下实际算出 " + distance + " 米");
    }

    @Test
    @DisplayName("跑步 3m/s、1 秒采样：本来就正常，修复后必须仍然正常")
    void runningStillWorks() {
        List<TrackPoint> track = walk(3.0, 1000, 120, 10.0);

        double distance = GpsUtil.totalDistanceMetersFiltered(track);

        assertTrue(distance > 300, "跑步 120 秒约 360 米，实际算出 " + distance + " 米");
    }

    @Test
    @DisplayName("静止抖动（原地 ±1 米、间隔 1 秒）必须仍然被滤掉，不能凭空产生距离")
    void stationaryJitterStillFiltered() {
        List<TrackPoint> track = new ArrayList<>();
        long t0 = 1_700_000_000_000L;
        double lat = 39.9042;
        double jitterMetersPerLatDegree = 111_320.0;
        for (int i = 0; i <= 120; i++) {
            TrackPoint p = new TrackPoint();
            // 在原地 ±1 米之间来回抖
            p.setLatitude(lat + (i % 2 == 0 ? 1.0 : -1.0) / jitterMetersPerLatDegree);
            p.setLongitude(116.4074);
            p.setAccuracy(8.0);
            p.setTimestamp(t0 + (long) i * 1000);
            track.add(p);
        }

        double distance = GpsUtil.totalDistanceMetersFiltered(track);

        // 抖了 120 次、每次位移 2 米 —— 若按「≥2 米一律计入」会得到约 240 米。
        // 但用户站在原地，这必须是噪声。
        assertTrue(distance < 30,
                "原地抖动不该产生距离，实际算出 " + distance + " 米");
    }

    @Test
    @DisplayName("间隔 ≥5 秒的真实小位移仍要计入（爬坡/慢走的老约定不能破）")
    void slowButLongIntervalStillCounts() {
        // 每 6 秒走 1 米（约 0.17 m/s，极慢），间隔 ≥5 秒 → 必须计入
        List<TrackPoint> track = walk(0.17, 6000, 60, 10.0);

        double distance = GpsUtil.totalDistanceMetersFiltered(track);

        assertTrue(distance > 5,
                "间隔 ≥5 秒的小位移必须采信，实际算出 " + distance + " 米");
    }

    @Test
    @DisplayName("精度差的点仍被忽略")
    void poorAccuracyStillIgnored() {
        List<TrackPoint> track = walk(1.4, 1000, 60, 80.0);

        assertEquals(0.0, GpsUtil.totalDistanceMetersFiltered(track), 0.001,
                "精度 80 米 > 35 米阈值，应全部忽略");
    }
}
