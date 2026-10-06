package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.dto.response.DistanceRepairResult;
import com.campusrun.server.entity.Activity;
import com.campusrun.server.mapper.ActivityMapper;
import com.campusrun.server.mapper.LeaderboardMapper;
import com.campusrun.server.mapper.UserGoalMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.model.TrackPoint;
import com.campusrun.server.service.DistanceRepairService;
import com.campusrun.server.util.GpsUtil;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

/**
 * {@link DistanceRepairService} 实现。
 *
 * <p>三步：① 重算单条记录的距离；② 按 activity 全量重算三种聚合；③ 重算连续打卡天数。
 * 全部在**一个事务**里执行 —— 中途失败会整体回滚，
 * 避免出现「记录改了但排行榜没改」的半成品状态（那比不修更糟，数据自相矛盾）。
 */
@Service
public class DistanceRepairServiceImpl implements DistanceRepairService {

    private static final Logger log = LoggerFactory.getLogger(DistanceRepairServiceImpl.class);

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    /** 明细最多返回多少条（避免响应体过大）。 */
    private static final int MAX_SAMPLES = 50;

    private final ActivityMapper activityMapper;
    private final UserStatsMapper userStatsMapper;
    private final LeaderboardMapper leaderboardMapper;
    private final UserGoalMapper goalMapper;
    private final ObjectMapper objectMapper;

    public DistanceRepairServiceImpl(ActivityMapper activityMapper,
                                     UserStatsMapper userStatsMapper,
                                     LeaderboardMapper leaderboardMapper,
                                     UserGoalMapper goalMapper,
                                     ObjectMapper objectMapper) {
        this.activityMapper = activityMapper;
        this.userStatsMapper = userStatsMapper;
        this.leaderboardMapper = leaderboardMapper;
        this.goalMapper = goalMapper;
        this.objectMapper = objectMapper;
    }

    @Override
    @Transactional
    public DistanceRepairResult repairZeroDistanceActivities(boolean dryRun) {
        DistanceRepairResult result = new DistanceRepairResult();
        result.setDryRun(dryRun);

        // ── ① 重算「距离为 0 但轨迹非空」的记录 ──────────────────────
        List<Activity> candidates = activityMapper.selectList(
                new LambdaQueryWrapper<Activity>()
                        .eq(Activity::getDistanceMeters, 0)
                        .isNotNull(Activity::getTrackJson)
                        .ne(Activity::getTrackJson, ""));

        result.setScannedZeroDistance(candidates.size());
        List<DistanceRepairResult.Item> samples = new ArrayList<>();
        long before = 0;
        long after = 0;
        int fixed = 0;
        int stillZero = 0;
        int unparsable = 0;

        for (Activity a : candidates) {
            before += a.getDistanceMeters() == null ? 0 : a.getDistanceMeters();
            List<TrackPoint> track = parseTrack(a.getTrackJson());
            if (track == null) {
                unparsable++;
                after += a.getDistanceMeters() == null ? 0 : a.getDistanceMeters();
                continue;
            }
            int recomputed = (int) Math.round(GpsUtil.totalDistanceMetersFiltered(track));
            after += recomputed;
            if (recomputed > 0) {
                fixed++;
                if (samples.size() < MAX_SAMPLES) {
                    samples.add(new DistanceRepairResult.Item(
                            a.getId(), a.getUserId(), 0, recomputed));
                }
                if (!dryRun) {
                    a.setDistanceMeters(recomputed);
                    activityMapper.updateById(a);
                }
            } else {
                stillZero++;
            }
        }

        result.setFixedActivities(fixed);
        result.setStillZero(stillZero);
        result.setUnparsableTracks(unparsable);
        result.setDistanceBefore(before);
        result.setDistanceAfter(after);
        result.setSamples(samples);

        if (dryRun) {
            log.info("[距离修复·预演] 扫描={}, 可修正={}, 仍为0={}, 解析失败={}, 里程 {} → {}",
                    candidates.size(), fixed, stillZero, unparsable, before, after);
            return result;
        }

        // ── ② 重算三处聚合（都只依赖 activity，因此可全量重算）────────
        result.setRebuiltUserStats(userStatsMapper.recomputeTotals());
        result.setRebuiltLeaderboardPeriods(rebuildLeaderboard());
        result.setRebuiltGoals(rebuildGoalProgress());
        rebuildStreaks();

        log.info("[距离修复·执行] 修正记录={}, 仍为0={}, 解析失败={}, 里程 {} → {}, 重算榜单period={}, 目标={}",
                fixed, stillZero, unparsable, before, after,
                result.getRebuiltLeaderboardPeriods(), result.getRebuiltGoals());
        return result;
    }

    /**
     * 重算日/周/月榜 + rolling30d。
     *
     * <p>对每个「有有效运动的日期」都重建该日、该周、该月三个 period。
     * 不用「所有日期笛卡尔积」是因为 period 只需被覆盖一次，
     * 用 DISTINCT 日期集合即可（同一周内多天会重复删建同一 period，结果仍正确，
     * 只是多做几次无副作用的删除）。
     */
    private int rebuildLeaderboard() {
        List<LocalDate> dates = leaderboardMapper.selectAllActivityDates();
        int rebuilt = 0;
        for (int type : new int[]{1, 2}) { // 1=跑步 2=骑行
            for (LocalDate date : dates) {
                LocalDateTime dayStart = date.atStartOfDay();
                LocalDateTime dayEnd = date.plusDays(1).atStartOfDay();

                // 日榜
                String dailyPeriod = date.toString();
                leaderboardMapper.deleteByPeriod("daily", dailyPeriod, type);
                leaderboardMapper.insertByPeriod("daily", dailyPeriod, type, dayStart, dayEnd);
                rebuilt++;

                // 周榜（周一为周期键）
                LocalDate monday = date.with(DayOfWeek.MONDAY);
                String weeklyPeriod = monday.toString();
                leaderboardMapper.deleteByPeriod("weekly", weeklyPeriod, type);
                leaderboardMapper.insertByPeriod("weekly", weeklyPeriod, type,
                        monday.atStartOfDay(), monday.plusDays(7).atStartOfDay());
                rebuilt++;

                // 月榜
                LocalDate firstDay = date.withDayOfMonth(1);
                String monthlyPeriod = String.format("%d-%02d", date.getYear(), date.getMonthValue());
                leaderboardMapper.deleteByPeriod("monthly", monthlyPeriod, type);
                leaderboardMapper.insertByPeriod("monthly", monthlyPeriod, type,
                        firstDay.atStartOfDay(), firstDay.plusMonths(1).atStartOfDay());
                rebuilt++;
            }

            // rolling30d（与 LeaderboardScheduler 完全同一套做法）
            LocalDateTime cutoff = LocalDate.now(ZONE).minusDays(30).atStartOfDay();
            leaderboardMapper.deleteRolling30d(type);
            leaderboardMapper.insertRolling30d(type, cutoff);
            rebuilt++;
        }
        return rebuilt;
    }

    private int rebuildGoalProgress() {
        List<Long> goalIds = goalMapper.selectAllGoalIds();
        for (Long id : goalIds) {
            goalMapper.recomputeProgress(id);
        }
        return goalIds.size();
    }

    /**
     * 重算连续打卡天数。
     *
     * <p>规则：从最近一次有效运动日期开始往回数连续天数；
     * 若最近一次运动**不是今天也不是昨天**，说明已断签，streak = 0
     * （与 BadgeScheduler.resetStreaks 的语义保持一致）。
     */
    private void rebuildStreaks() {
        LocalDate today = LocalDate.now(ZONE);
        for (Long userId : activityMapper.selectDistinctUserIdsWithValidActivity()) {
            computeAndSaveStreak(userId, today);
        }
    }

    private void computeAndSaveStreak(long userId, LocalDate today) {
        List<LocalDate> dates = userStatsMapper.selectActivityDates(userId);
        if (dates.isEmpty()) {
            return;
        }
        LocalDate last = dates.get(0);
        // 最近一次运动既不是今天也不是昨天 → 已断签
        if (ChronoUnit.DAYS.between(last, today) > 1) {
            userStatsMapper.updateStreak(userId, 0, last);
            return;
        }
        int streak = 1;
        LocalDate cursor = last;
        for (int i = 1; i < dates.size(); i++) {
            LocalDate prev = dates.get(i);
            if (ChronoUnit.DAYS.between(prev, cursor) == 1) {
                streak++;
                cursor = prev;
            } else {
                break;
            }
        }
        userStatsMapper.updateStreak(userId, streak, last);
    }

    /** 解析轨迹 JSON；失败返回 null（不抛异常，避免一条脏数据让整批修复中止）。 */
    private List<TrackPoint> parseTrack(String json) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<TrackPoint>>() {
            });
        } catch (Exception e) {
            log.warn("轨迹 JSON 解析失败，跳过该记录: {}", e.getMessage());
            return null;
        }
    }
}
