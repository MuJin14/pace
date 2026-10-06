package com.campusrun.server.service.impl;

import com.campusrun.server.dto.response.DistanceRepairResult;
import com.campusrun.server.entity.Activity;
import com.campusrun.server.entity.LeaderboardStat;
import com.campusrun.server.entity.UserStats;
import com.campusrun.server.mapper.ActivityMapper;
import com.campusrun.server.mapper.LeaderboardMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.service.DistanceRepairService;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 历史「距离为 0」记录修复的集成测试（H2 内存库）。
 *
 * <p>背景：距离过滤算法在 2026-10 修复后只对新运动生效，
 * 库里旧记录仍是 0。本测试验证修复服务真的能把旧记录**连同三处聚合值**一起改对。
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class DistanceRepairServiceImplTest {

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final long USER_ID = 88_001L;

    @Autowired
    private DistanceRepairService repairService;
    @Autowired
    private ActivityMapper activityMapper;
    @Autowired
    private UserStatsMapper userStatsMapper;
    @Autowired
    private LeaderboardMapper leaderboardMapper;

    /**
     * 造一条「慢走」轨迹的 JSON：1.4 m/s、1 秒采样、120 秒 ≈ 168 米。
     *
     * <p>这正是旧算法的死区：每段 1.4 米 < 2 米、间隔 1 秒 < 5 秒 → 全部丢弃 → 0 米。
     */
    private String slowWalkTrackJson() {
        double lat = 39.9042;
        double metersPerLatDegree = 111_320.0;
        long t0 = 1_700_000_000_000L;
        List<String> points = new ArrayList<>();
        for (int i = 0; i <= 120; i++) {
            points.add(String.format(
                    "{\"latitude\":%.7f,\"longitude\":116.4074,\"timestamp\":%d,\"accuracy\":10.0}",
                    lat, t0 + i * 1000L));
            lat += 1.4 / metersPerLatDegree;
        }
        return "[" + String.join(",", points) + "]";
    }

    private Activity insertStoredActivity(String trackJson, int distance, LocalDateTime start) {
        Activity a = new Activity();
        a.setUserId(USER_ID);
        a.setType(1);
        a.setMode(1);
        a.setInvalid(0);
        a.setDistanceMeters(distance);
        a.setDurationSeconds(120);
        a.setStartTime(start);
        a.setEndTime(start.plusSeconds(120));
        a.setStartLat(new java.math.BigDecimal("39.9042000"));
        a.setStartLng(new java.math.BigDecimal("116.4074000"));
        a.setTrackJson(trackJson);
        activityMapper.insert(a);
        return a;
    }

    private void ensureStatsRow() {
        UserStats stats = new UserStats();
        stats.setUserId(USER_ID);
        stats.setTotalDistanceMeters(0);
        stats.setTotalActivityCount(0);
        stats.setStreakDays(0);
        userStatsMapper.insert(stats);
    }

    @Test
    void dryRun_doesNotWriteAnything() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        Activity stored = insertStoredActivity(slowWalkTrackJson(), 0, start);

        DistanceRepairResult result = repairService.repairZeroDistanceActivities(true);

        assertTrue(result.isDryRun());
        assertTrue(result.getScannedZeroDistance() >= 1,
                "应扫到这条 0 距离记录，实际 " + result.getScannedZeroDistance());
        assertTrue(result.getFixedActivities() >= 1,
                "预演也应报告「可修正」条数，实际 " + result.getFixedActivities());
        assertTrue(result.getDistanceAfter() > result.getDistanceBefore(),
                "预演应算出修正后的里程大于修正前");

        // 关键：预演**不能**写库
        Activity after = activityMapper.selectById(stored.getId());
        assertEquals(0, after.getDistanceMeters(), "dryRun 不允许改动数据库");
    }

    @Test
    void repair_fixesStoredDistanceAndRebuildsAggregates() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        Activity stored = insertStoredActivity(slowWalkTrackJson(), 0, start);
        ensureStatsRow();

        DistanceRepairResult result = repairService.repairZeroDistanceActivities(false);

        assertTrue(result.getFixedActivities() >= 1);

        // ① 记录本身被修正：慢走 120 秒应算出上百米，绝不能还是 0
        Activity fixed = activityMapper.selectById(stored.getId());
        assertTrue(fixed.getDistanceMeters() > 100,
                "修复后应算出约 168 米，实际 " + fixed.getDistanceMeters());

        // ② user_stats 累计里程被重算（原来错记为 0）
        UserStats stats = userStatsMapper.selectById(USER_ID);
        assertNotNull(stats);
        assertEquals(fixed.getDistanceMeters(), stats.getTotalDistanceMeters(),
                "累计里程必须与记录一致：记录对了但累计还是 0，用户看到的仍是错的");
        assertTrue(stats.getTotalActivityCount() >= 1);
    }

    @Test
    void repairedLeaderboardMatchesActivity() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        Activity stored = insertStoredActivity(slowWalkTrackJson(), 0, start);

        repairService.repairZeroDistanceActivities(false);
        Activity fixed = activityMapper.selectById(stored.getId());

        // 日榜该用户的值必须等于这条记录的距离
        String period = start.toLocalDate().toString();
        Integer daily = leaderboardMapper.selectDistance("daily", period, 1, USER_ID);
        assertNotNull(daily, "修复后日榜应出现该用户");
        assertEquals(fixed.getDistanceMeters(), daily,
                "榜单值必须由 activity 重算得出，不能沿用旧的 0");
    }

    @Test
    void repair_isIdempotent() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        insertStoredActivity(slowWalkTrackJson(), 0, start);

        DistanceRepairResult first = repairService.repairZeroDistanceActivities(false);
        assertTrue(first.getFixedActivities() >= 1);

        // 第二次执行：已经没有「距离为 0 但轨迹非空」的可修记录了
        DistanceRepairResult second = repairService.repairZeroDistanceActivities(false);
        assertEquals(0, second.getFixedActivities(),
                "幂等：第二次不应再修正任何记录，实际 " + second.getFixedActivities());
        assertEquals(0, second.getScannedZeroDistance(),
                "第一次修完后不再有 0 距离记录");
    }

    @Test
    void unparsableTrack_isSkippedNotFatal() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        Activity broken = insertStoredActivity("{ this is not json", 0, start);
        Activity good = insertStoredActivity(slowWalkTrackJson(), 0, start);

        DistanceRepairResult result = repairService.repairZeroDistanceActivities(false);

        assertTrue(result.getUnparsableTracks() >= 1, "应记录解析失败条数");
        // 关键：一条脏数据不能中止整批修复
        assertTrue(result.getFixedActivities() >= 1, "其余记录仍应被修好");
        assertEquals(0, activityMapper.selectById(broken.getId()).getDistanceMeters(),
                "解析失败的记录保持原样，不猜、不猜错");
        assertTrue(activityMapper.selectById(good.getId()).getDistanceMeters() > 100);
    }

    @Test
    void activityWithoutTrack_isLeftAlone() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        Activity noTrack = insertStoredActivity(null, 0, start);

        DistanceRepairResult result = repairService.repairZeroDistanceActivities(false);

        // 没有轨迹就没有信息可算 —— 不该把它的距离"猜"成别的值
        assertEquals(0, activityMapper.selectById(noTrack.getId()).getDistanceMeters());
        assertEquals(0, result.getUnparsableTracks(),
                "轨迹为 null 的记录根本没进候选集，不该计为解析失败");
    }

    @Test
    void invalidActivity_doesNotPolluteLeaderboard() {
        LocalDateTime start = LocalDate.now(ZONE).atTime(8, 0);
        // 有效记录（会被修）
        insertStoredActivity(slowWalkTrackJson(), 0, start);
        // 无效记录（反作弊命中，不该进榜）
        Activity bad = insertStoredActivity(slowWalkTrackJson(), 0, start);
        bad.setInvalid(1);
        bad.setInvalidReason("TEST");
        activityMapper.updateById(bad);

        repairService.repairZeroDistanceActivities(false);

        Integer daily = leaderboardMapper.selectDistance("daily", start.toLocalDate().toString(), 1, USER_ID);
        if (daily != null) {
            Activity good = activityMapper.selectList(new LambdaQueryWrapper<Activity>()
                    .eq(Activity::getUserId, USER_ID)
                    .eq(Activity::getInvalid, 0)).get(0);
            assertEquals(good.getDistanceMeters(), daily,
                    "榜单不能把 invalid=1 的记录也算进去");
        }
    }
}
