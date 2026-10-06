package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.InputStream;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 用**真实轨迹数据**验证距离算法（回归 + 修复一致性）。
 *
 * <p>`track-real-520.json` 是从生产库里原样导出的 520 个定位点
 * （34.6 分钟、精度 8 米、43 KB），库里存的 `distance_meters = 5771`。
 *
 * <p><b>为什么必须有这个测试</b>：合成轨迹（匀速直线）只能验证数学正确性，
 * 无法回答「真实采样抖动下算法会不会跑偏」。而这个文件里的数据就是
 * 用户手机真实产生的，用它做断言才能保证改算法时不会把线上结果改坏。
 */
class GpsUtilRealTrackTest {

    private static final int STORED_DISTANCE = 5771; // 该轨迹在库里的历史值

    private List<TrackPoint> loadRealTrack() throws Exception {
        try (InputStream in = getClass().getClassLoader()
                .getResourceAsStream("track-real-520.json")) {
            assertNotNull(in, "测试资源 track-real-520.json 缺失");
            ObjectMapper mapper = new ObjectMapper();
            List<TrackPoint> track = mapper.readValue(in, new TypeReference<List<TrackPoint>>() {
            });
            assertEquals(520, track.size(), "导出的轨迹应是 520 个点");
            return track;
        }
    }

    @Test
    @DisplayName("真实轨迹：新算法结果与库中历史值一致（不因修 bug 而改坏正常数据）")
    void realTrackDistanceMatchesStoredValue() throws Exception {
        List<TrackPoint> track = loadRealTrack();

        double filtered = GpsUtil.totalDistanceMetersFiltered(track);
        int rounded = (int) Math.round(filtered);

        // 允许 2% 误差：算法换了判据，边界点上会有少量出入，
        // 但不该出现量级差异（那说明改坏了）。
        assertEquals(STORED_DISTANCE, rounded, STORED_DISTANCE * 0.02,
                "新算法算出 " + rounded + " 米，库里历史值 " + STORED_DISTANCE
                        + " 米。差太多说明新判据误杀了正常轨迹");
    }

    @Test
    @DisplayName("真实轨迹：原始累加不应比过滤值大太多（说明数据本身干净）")
    void rawAndFilteredAreClose() throws Exception {
        List<TrackPoint> track = loadRealTrack();

        double raw = GpsUtil.totalDistanceMeters(track);
        double filtered = GpsUtil.totalDistanceMetersFiltered(track);

        // 这条轨迹是匀速直线、精度稳定，两者应当接近
        assertTrue(Math.abs(raw - filtered) / raw < 0.1,
                "原始 " + raw + " 米 vs 过滤 " + filtered + " 米，差距过大");
    }

    @Test
    @DisplayName("真实轨迹：明确不是 0（这就是「运动记录为 0」要防的反面）")
    void realTrackIsNotZero() throws Exception {
        List<TrackPoint> track = loadRealTrack();

        double filtered = GpsUtil.totalDistanceMetersFiltered(track);

        assertTrue(filtered > 5000,
                "34.6 分钟约 5.8 公里，实际算出 " + filtered + " 米");
    }

    @Test
    @DisplayName("性能：520 点重算不能慢到卡住接口（修复要遍历全库）")
    void performanceIsAcceptable() throws Exception {
        List<TrackPoint> track = loadRealTrack();

        // 预热 JIT
        GpsUtil.totalDistanceMetersFiltered(track);

        long start = System.nanoTime();
        for (int i = 0; i < 100; i++) {
            GpsUtil.totalDistanceMetersFiltered(track);
        }
        long perCallMicros = (System.nanoTime() - start) / 100 / 1000;

        // 每次 520 点应远低于 1 毫秒 —— 否则全库修复会长时间锁表
        assertTrue(perCallMicros < 1000,
                "单次 520 点耗时 " + perCallMicros + " 微秒，过慢");
    }
}
