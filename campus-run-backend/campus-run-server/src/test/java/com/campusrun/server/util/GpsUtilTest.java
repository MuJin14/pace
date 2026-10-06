package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class GpsUtilTest {

    @Test
    void distanceMeters_samePoint_returnsZero() {
        assertEquals(0.0, GpsUtil.distanceMeters(39.9, 116.4, 39.9, 116.4), 0.001);
    }

    @Test
    void distanceMeters_oneDegreeLatitude_about111km() {
        double d = GpsUtil.distanceMeters(39.0, 116.0, 40.0, 116.0);
        assertEquals(111_195.0, d, 111_195.0 * 0.01);
    }

    @Test
    void totalDistance_emptyOrSingle_returnsZero() {
        assertEquals(0.0, GpsUtil.totalDistanceMeters(null), 0.001);
        assertEquals(0.0, GpsUtil.totalDistanceMeters(List.of()), 0.001);
        assertEquals(0.0, GpsUtil.totalDistanceMeters(
                List.of(new TrackPoint(39.0, 116.0, 1L, 10.0))), 0.001);
    }

    @Test
    void totalDistance_sumOfSegments() {
        List<TrackPoint> track = List.of(
                new TrackPoint(39.0, 116.0, 1L, 10.0),
                new TrackPoint(39.0, 116.001, 2L, 10.0),
                new TrackPoint(39.0, 116.002, 3L, 10.0));

        double seg1 = GpsUtil.distanceMeters(39.0, 116.0, 39.0, 116.001);
        double seg2 = GpsUtil.distanceMeters(39.0, 116.001, 39.0, 116.002);

        assertEquals(seg1 + seg2, GpsUtil.totalDistanceMeters(track), 0.001);
    }

    /**
     * 精度过滤的核心价值：脏点会把距离算成好几倍。
     *
     * <p>这是用户口中「定位不准」的真正机制 —— 不是 GPS 坏了，
     * 而是误差 50 米的点被当成真实位移累加了进去。
     */
    @Test
    void filteredDistance_ignoresPoorAccuracyPoints() {
        // 沿经度方向每步约 85 米（0.001° ≈ 85m），共 5 步 ≈ 340 米真实距离。
        // 第 3 个点精度 60 米且位置被"甩"出去 0.01°（≈850 米），
        // 未过滤时这一个点就会多算约 1700 米。
        List<TrackPoint> track = List.of(
                new TrackPoint(39.0, 116.000, 0L, 8.0),
                new TrackPoint(39.0, 116.001, 10_000L, 8.0),
                new TrackPoint(39.0, 116.011, 20_000L, 60.0), // 脏点
                new TrackPoint(39.0, 116.002, 30_000L, 8.0),
                new TrackPoint(39.0, 116.003, 40_000L, 8.0));

        double raw = GpsUtil.totalDistanceMeters(track);
        double filtered = GpsUtil.totalDistanceMetersFiltered(track);

        // 原始计算被脏点严重夸大（超过 3 倍）
        assertEquals(true, raw > filtered * 3,
                "原始距离应被脏点严重夸大，实际 raw=" + raw + " filtered=" + filtered);

        // 过滤后约为 3 段 × 85 米 ≈ 260 米
        // （脏点被丢掉后，第 2 → 第 4 点直接相连，比"绕过去"略短，
        //   这是跳点的已知代价：宁可少算一点，也不凭空多算 1700 米）
        assertEquals(260.0, filtered, 30.0,
                "过滤后应接近真实距离，实际 " + filtered);
    }

    /** 静止抖动不应累加距离（否则「站着不动」也会涨公里数）。 */
    @Test
    void filteredDistance_ignoresStationaryJitter() {
        // 每 1 秒抖动约 1 米，共 60 次：真实位移 0，原始计算会累加约 60 米
        List<TrackPoint> track = new java.util.ArrayList<>();
        for (int i = 0; i < 60; i++) {
            double latOffset = (i % 2 == 0) ? 0.0 : 0.00001; // ≈1.1 米来回
            track.add(new TrackPoint(39.0 + latOffset, 116.0, i * 1000L, 5.0));
        }

        double raw = GpsUtil.totalDistanceMeters(track);
        double filtered = GpsUtil.totalDistanceMetersFiltered(track);

        assertEquals(true, raw > 50, "原始计算应累加出可观的假距离，实际 " + raw);
        assertEquals(0.0, filtered, 0.001,
                "原地抖动应被完全过滤，实际 " + filtered);
    }

    /**
     * 慢走不能被过滤掉：5 秒只走 1 米是真实的（爬坡/慢走），
     * 高频抖动才会「稳定每 5 秒挪 1 米」。
     */
    @Test
    void filteredDistance_keepsSlowButRealMovement() {
        // 每 5 秒前进约 1.1 米
        List<TrackPoint> track = new java.util.ArrayList<>();
        for (int i = 0; i < 11; i++) {
            track.add(new TrackPoint(39.0 + i * 0.00001, 116.0, i * 5000L, 5.0));
        }

        double filtered = GpsUtil.totalDistanceMetersFiltered(track);
        assertEquals(true, filtered > 8,
                "5 秒 1.1 米的慢走应被计入，实际 " + filtered);
    }

    /** 精度缺失（老数据）时不做过滤，保持向后兼容。 */
    @Test
    void filteredDistance_withoutAccuracyField_stillCounts() {
        List<TrackPoint> track = List.of(
                new TrackPoint(39.0, 116.000, 0L, null),
                new TrackPoint(39.0, 116.001, 10_000L, null),
                new TrackPoint(39.0, 116.002, 20_000L, null));

        assertEquals(GpsUtil.totalDistanceMeters(track),
                GpsUtil.totalDistanceMetersFiltered(track), 0.001);
    }
}
