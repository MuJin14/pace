package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.dto.response.MyRankResponse;
import com.campusrun.server.enums.LeaderboardScope;
import com.campusrun.server.mapper.LeaderboardMapper;
import com.campusrun.server.service.LeaderboardService;
import com.campusrun.server.service.UserRelationResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.List;

@Service
public class LeaderboardServiceImpl implements LeaderboardService {

    private static final Logger log = LoggerFactory.getLogger(LeaderboardServiceImpl.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final int[] TYPES = {1, 2};

    private final LeaderboardMapper leaderboardMapper;
    private final UserRelationResolver relationResolver;

    /** Spring 用这个构造器（显式标注，避免与下方兼容构造器歧义）。 */
    @org.springframework.beans.factory.annotation.Autowired
    public LeaderboardServiceImpl(LeaderboardMapper leaderboardMapper,
                                  UserRelationResolver relationResolver) {
        this.leaderboardMapper = leaderboardMapper;
        this.relationResolver = relationResolver;
    }

    /** 兼容构造器（既有单测用，不涉及 relation）。 */
    public LeaderboardServiceImpl(LeaderboardMapper leaderboardMapper) {
        this(leaderboardMapper, null);
    }

    @Override
    public void recordActivity(Long userId, int distanceMeters, LocalDateTime startTime, int activityType) {
        LocalDate date = startTime.toLocalDate();
        String dailyPeriod = date.toString();
        String weeklyPeriod = date.with(DayOfWeek.MONDAY).toString();
        String monthlyPeriod = String.format("%d-%02d", date.getYear(), date.getMonthValue());

        leaderboardMapper.upsertDistance(userId, LeaderboardScope.DAILY.getCode(), dailyPeriod, activityType, distanceMeters);
        leaderboardMapper.upsertDistance(userId, LeaderboardScope.WEEKLY.getCode(), weeklyPeriod, activityType, distanceMeters);
        leaderboardMapper.upsertDistance(userId, LeaderboardScope.MONTHLY.getCode(), monthlyPeriod, activityType, distanceMeters);
    }

    @Override
    public PageResponse<LeaderboardEntryResponse> getBoard(String scope, String period, Integer type,
                                                          long page, long size, Long currentUserId) {
        LeaderboardScope scopeEnum = validateScope(scope);
        int typeValue = validateType(type);
        String resolvedPeriod = resolvePeriod(scopeEnum, period);

        long safePage = Math.max(1, page);
        long safeSize = Math.min(100, Math.max(1, size));
        long offset = (safePage - 1) * safeSize;

        long total = leaderboardMapper.countBoard(scopeEnum.getCode(), resolvedPeriod, typeValue);
        List<LeaderboardEntryResponse> rows = leaderboardMapper.selectBoardPage(
                scopeEnum.getCode(), resolvedPeriod, typeValue, offset, safeSize);
        for (int i = 0; i < rows.size(); i++) {
            rows.get(i).setRank(offset + i + 1);
        }

        // 补社交关系：让用户能直接在榜单上加好友，且按钮状态正确。
        if (relationResolver != null && currentUserId != null) {
            for (LeaderboardEntryResponse row : rows) {
                row.setRelation(
                        relationResolver.resolve(currentUserId, row.getUserId()).getCode());
            }
        }

        // 补「与前后名的差距」。只在本页内计算：跨页时需要额外查询，
        // 而差距的价值主要在相邻名次（第 1 名和第 20 名的差额意义不大）。
        for (int i = 0; i < rows.size(); i++) {
            Integer mine = rows.get(i).getDistanceMeters();
            if (mine == null) {
                continue;
            }
            if (i > 0) {
                Integer ahead = rows.get(i - 1).getDistanceMeters();
                if (ahead != null) {
                    rows.get(i).setGapToAheadMeters(Math.max(0, ahead - mine));
                }
            } else if (offset > 0) {
                // 本页第一条且不是全局第一：它前面的人不在本次结果里，
                // 留空而不是错误地当成「第 1 名」。
                rows.get(i).setGapToAheadMeters(null);
            }
            if (i + 1 < rows.size()) {
                Integer behind = rows.get(i + 1).getDistanceMeters();
                if (behind != null) {
                    rows.get(i).setGapToBehindMeters(Math.max(0, mine - behind));
                }
            }
        }
        return new PageResponse<>(total, safePage, safeSize, rows);
    }

    @Override
    public MyRankResponse getMyRank(String scope, String period, Integer type, Long userId) {
        LeaderboardScope scopeEnum = validateScope(scope);
        int typeValue = validateType(type);
        String resolvedPeriod = resolvePeriod(scopeEnum, period);

        long total = leaderboardMapper.countBoard(scopeEnum.getCode(), resolvedPeriod, typeValue);
        Integer distance = leaderboardMapper.selectDistance(scopeEnum.getCode(), resolvedPeriod, typeValue, userId);
        if (distance == null) {
            return new MyRankResponse(null, 0L, total);
        }
        long rank = leaderboardMapper.countGreaterThan(scopeEnum.getCode(), resolvedPeriod, typeValue, distance) + 1;
        return new MyRankResponse(rank, distance.longValue(), total);
    }

    @Override
    @Transactional
    public void rebuildRolling30d() {
        log.info("定时任务开始：rebuildRolling30d");
        long start = System.currentTimeMillis();
        LocalDateTime cutoff = LocalDate.now(ZONE).minusDays(30).atStartOfDay();
        int count = 0;
        for (int type : TYPES) {
            leaderboardMapper.deleteRolling30d(type);
            count += leaderboardMapper.insertRolling30d(type, cutoff);
        }
        log.info("定时任务完成：rebuildRolling30d, count={}, costMs={}",
                count, System.currentTimeMillis() - start);
    }

    @Override
    @Transactional
    public void cleanupExpired() {
        log.info("定时任务开始：cleanupExpired");
        long start = System.currentTimeMillis();
        LocalDate today = LocalDate.now(ZONE);
        String dailyBefore = today.minusDays(32).toString();
        String weeklyBefore = today.minusWeeks(12).with(DayOfWeek.MONDAY).toString();
        String monthlyBefore = YearMonth.now(ZONE).minusMonths(12).toString();
        int count = 0;
        for (int type : TYPES) {
            count += leaderboardMapper.deleteExpired(LeaderboardScope.DAILY.getCode(), type, dailyBefore);
            count += leaderboardMapper.deleteExpired(LeaderboardScope.WEEKLY.getCode(), type, weeklyBefore);
            count += leaderboardMapper.deleteExpired(LeaderboardScope.MONTHLY.getCode(), type, monthlyBefore);
        }
        log.info("定时任务完成：cleanupExpired, count={}, costMs={}",
                count, System.currentTimeMillis() - start);
    }

    private LeaderboardScope validateScope(String scope) {
        LeaderboardScope scopeEnum = LeaderboardScope.fromCode(scope);
        if (scopeEnum == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "榜单维度不合法");
        }
        return scopeEnum;
    }

    private int validateType(Integer type) {
        if (type == null || (type != 1 && type != 2)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "运动类型不合法");
        }
        return type;
    }

    private String resolvePeriod(LeaderboardScope scope, String period) {
        if (scope == LeaderboardScope.ROLLING_30D) {
            return "CURRENT";
        }
        if (period != null && !period.isBlank()) {
            validatePeriod(scope, period);
            return period;
        }
        LocalDate today = LocalDate.now(ZONE);
        return switch (scope) {
            case DAILY -> today.toString();
            case WEEKLY -> today.with(DayOfWeek.MONDAY).toString();
            case MONTHLY -> String.format("%d-%02d", today.getYear(), today.getMonthValue());
            case ROLLING_30D -> "CURRENT";
        };
    }

    private void validatePeriod(LeaderboardScope scope, String period) {
        try {
            switch (scope) {
                case DAILY, WEEKLY -> LocalDate.parse(period);
                case MONTHLY -> YearMonth.parse(period);
                case ROLLING_30D -> {
                }
            }
        } catch (DateTimeParseException e) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "榜单周期格式不合法");
        }
    }
}
