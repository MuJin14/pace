package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.dto.response.BadgeResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;
import com.campusrun.server.entity.Badge;
import com.campusrun.server.entity.UserBadge;
import com.campusrun.server.entity.UserGoal;
import com.campusrun.server.entity.UserStats;
import com.campusrun.server.enums.GoalStatus;
import com.campusrun.server.event.BadgeAwardedEvent;
import com.campusrun.server.mapper.BadgeMapper;
import com.campusrun.server.mapper.UserBadgeMapper;
import com.campusrun.server.mapper.UserGoalMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.service.BadgeService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class BadgeServiceImpl implements BadgeService {

    private static final Logger log = LoggerFactory.getLogger(BadgeServiceImpl.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final UserStatsMapper userStatsMapper;
    private final BadgeMapper badgeMapper;
    private final UserBadgeMapper userBadgeMapper;
    private final UserGoalMapper goalMapper;
    private final ApplicationEventPublisher eventPublisher;

    public BadgeServiceImpl(UserStatsMapper userStatsMapper, BadgeMapper badgeMapper,
                            UserBadgeMapper userBadgeMapper, UserGoalMapper goalMapper,
                            ApplicationEventPublisher eventPublisher) {
        this.userStatsMapper = userStatsMapper;
        this.badgeMapper = badgeMapper;
        this.userBadgeMapper = userBadgeMapper;
        this.goalMapper = goalMapper;
        this.eventPublisher = eventPublisher;
    }

    @Override
    public List<BadgeResponse> listAll(Long userId) {
        List<Badge> all = badgeMapper.selectList(new LambdaQueryWrapper<Badge>()
                .eq(Badge::getEnabled, 1)
                .orderByAsc(Badge::getSort)
                .orderByAsc(Badge::getId));

        Map<Long, LocalDateTime> awardedMap = userBadgeMapper.selectList(
                        new LambdaQueryWrapper<UserBadge>().eq(UserBadge::getUserId, userId))
                .stream()
                .collect(Collectors.toMap(UserBadge::getBadgeId, UserBadge::getAwardedAt, (a, b) -> a));

        return all.stream()
                .map(badge -> toResponse(badge, awardedMap.containsKey(badge.getId()), awardedMap.get(badge.getId())))
                .toList();
    }

    @Override
    public List<UserBadgeResponse> listMine(Long userId) {
        List<UserBadge> owned = userBadgeMapper.selectList(new LambdaQueryWrapper<UserBadge>()
                .eq(UserBadge::getUserId, userId)
                .orderByDesc(UserBadge::getAwardedAt));
        if (owned.isEmpty()) {
            return List.of();
        }

        List<Long> badgeIds = owned.stream().map(UserBadge::getBadgeId).toList();
        Map<Long, Badge> badgeMap = badgeMapper.selectBatchIds(badgeIds).stream()
                .collect(Collectors.toMap(Badge::getId, badge -> badge));

        return owned.stream().map(userBadge -> {
            Badge badge = badgeMap.get(userBadge.getBadgeId());
            UserBadgeResponse response = new UserBadgeResponse();
            response.setBadgeId(userBadge.getBadgeId());
            response.setAwardedAt(userBadge.getAwardedAt());
            if (badge != null) {
                response.setCode(badge.getCode());
                response.setName(badge.getName());
                response.setIcon(badge.getIcon());
                response.setDescription(badge.getDescription());
            }
            return response;
        }).toList();
    }

    /**
     * 更新用户统计后遍历启用勋章判发策略，命中则落库并发事件。
     */
    @Override
    public void evaluateOnActivity(Long userId, int distanceMeters, LocalDateTime startTime) {
        LocalDate activityDate = startTime.atZone(ZONE).toLocalDate();

        UserStats stats = userStatsMapper.selectById(userId);
        if (stats == null) {
            stats = new UserStats();
            stats.setUserId(userId);
            stats.setTotalDistanceMeters(distanceMeters);
            stats.setTotalActivityCount(1);
            stats.setStreakDays(1);
            stats.setLastActivityDate(activityDate);
            stats.setWeeklyGoalCompletedCount(0);
            userStatsMapper.insert(stats);
        } else {
            int newStreak = computeStreak(stats.getStreakDays(), stats.getLastActivityDate(), activityDate);
            LocalDate newLast = resolveLastDate(stats.getLastActivityDate(), activityDate);
            stats.setTotalDistanceMeters(safe(stats.getTotalDistanceMeters()) + distanceMeters);
            stats.setTotalActivityCount(safe(stats.getTotalActivityCount()) + 1);
            stats.setStreakDays(newStreak);
            stats.setLastActivityDate(newLast);
            userStatsMapper.updateById(stats);
        }

        awardEligible(userId, safe(stats.getTotalDistanceMeters()), safe(stats.getTotalActivityCount()),
                safe(stats.getStreakDays()), safe(stats.getWeeklyGoalCompletedCount()));
    }

    @Override
    @Transactional
    public void resetStreaks() {
        log.info("定时任务开始：resetStreaks");
        long start = System.currentTimeMillis();
        int count = userStatsMapper.resetStreaks(LocalDate.now(ZONE).minusDays(1));
        log.info("定时任务完成：resetStreaks, count={}, costMs={}",
                count, System.currentTimeMillis() - start);
    }

    @Override
    @Transactional
    public void checkWeeklyGoals() {
        log.info("定时任务开始：checkWeeklyGoals");
        long start = System.currentTimeMillis();
        LocalDate today = LocalDate.now(ZONE);
        List<UserGoal> ended = goalMapper.selectEndedWeeklyGoals(today);
        for (UserGoal goal : ended) {
            if (goal.getCurrentDistanceMeters() >= goal.getTargetDistanceMeters()) {
                goal.setStatus(GoalStatus.COMPLETED.getCode());
                goalMapper.updateById(goal);

                userStatsMapper.incrementWeeklyGoalCompleted(goal.getUserId());
                UserStats stats = userStatsMapper.selectById(goal.getUserId());
                if (stats != null) {
                    awardEligible(goal.getUserId(), safe(stats.getTotalDistanceMeters()),
                            safe(stats.getTotalActivityCount()), safe(stats.getStreakDays()),
                            safe(stats.getWeeklyGoalCompletedCount()));
                }
            } else {
                goal.setStatus(GoalStatus.EXPIRED.getCode());
                goalMapper.updateById(goal);
            }
        }
        log.info("定时任务完成：checkWeeklyGoals, count={}, costMs={}",
                ended.size(), System.currentTimeMillis() - start);
    }

    private void awardEligible(Long userId, int totalDistance, int activityCount, int streakDays, int weeklyGoalCompleted) {
        List<Badge> eligible = badgeMapper.selectEligible(totalDistance, activityCount, streakDays, weeklyGoalCompleted);
        for (Badge badge : eligible) {
            if (userBadgeMapper.insertIgnore(userId, badge.getId()) > 0) {
                log.info("判发勋章，userId={}, badgeCode={}", userId, badge.getCode());
                eventPublisher.publishEvent(new BadgeAwardedEvent(userId, badge));
            }
        }
    }

    private int computeStreak(Integer prevStreak, LocalDate prevLast, LocalDate activityDate) {
        if (prevLast == null) {
            return 1;
        }
        if (activityDate.isBefore(prevLast) || activityDate.isEqual(prevLast)) {
            return safe(prevStreak);
        }
        if (activityDate.equals(prevLast.plusDays(1))) {
            return safe(prevStreak) + 1;
        }
        return 1;
    }

    private LocalDate resolveLastDate(LocalDate prevLast, LocalDate activityDate) {
        if (prevLast == null) {
            return activityDate;
        }
        return activityDate.isAfter(prevLast) ? activityDate : prevLast;
    }

    private BadgeResponse toResponse(Badge badge, boolean earned, LocalDateTime awardedAt) {
        BadgeResponse response = new BadgeResponse();
        response.setId(badge.getId());
        response.setCode(badge.getCode());
        response.setName(badge.getName());
        response.setIcon(badge.getIcon());
        response.setDescription(badge.getDescription());
        response.setRuleType(badge.getRuleType());
        response.setRuleValue(badge.getRuleValue());
        response.setEarned(earned);
        response.setAwardedAt(awardedAt);
        return response;
    }

    private int safe(Integer value) {
        return value == null ? 0 : value;
    }
}
