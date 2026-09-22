package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.Badge;
import com.campusrun.server.entity.UserBadge;
import com.campusrun.server.entity.UserGoal;
import com.campusrun.server.entity.UserStats;
import com.campusrun.server.enums.GoalStatus;
import com.campusrun.server.mapper.BadgeMapper;
import com.campusrun.server.mapper.UserBadgeMapper;
import com.campusrun.server.mapper.UserGoalMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.BadgeService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class BadgeServiceImplTest {

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private BadgeService badgeService;

    @Autowired
    private AuthService authService;

    @Autowired
    private BadgeMapper badgeMapper;

    @Autowired
    private UserBadgeMapper userBadgeMapper;

    @Autowired
    private UserStatsMapper userStatsMapper;

    @Autowired
    private UserGoalMapper goalMapper;

    private Long register(String phone) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname("徽章" + phone.substring(phone.length() - 4));
        LoginResponse resp = authService.register(req);
        return resp.getUserId();
    }

    private Badge insertBadge(String code, String ruleType, int value) {
        Badge badge = new Badge();
        badge.setCode(code);
        badge.setName(code);
        badge.setRuleType(ruleType);
        badge.setRuleValue(value);
        badge.setEnabled(1);
        badge.setSort(0);
        badgeMapper.insert(badge);
        return badge;
    }

    private boolean hasBadge(Long userId, Long badgeId) {
        return userBadgeMapper.selectCount(new LambdaQueryWrapper<UserBadge>()
                .eq(UserBadge::getUserId, userId)
                .eq(UserBadge::getBadgeId, badgeId)) > 0;
    }

    @Test
    void evaluateOnActivity_awardsDistanceAndCountBadges() {
        Long userId = register("13500000001");
        Badge distanceBadge = insertBadge("d_1000", "total_distance", 1000);
        Badge countBadge = insertBadge("c_1", "activity_count", 1);

        badgeService.evaluateOnActivity(userId, 5000, LocalDateTime.of(2026, 1, 1, 8, 0));

        assertTrue(hasBadge(userId, distanceBadge.getId()));
        assertTrue(hasBadge(userId, countBadge.getId()));
    }

    @Test
    void evaluateOnActivity_noDuplicateAward() {
        Long userId = register("13500000002");
        Badge distanceBadge = insertBadge("d_1000_b", "total_distance", 1000);

        badgeService.evaluateOnActivity(userId, 5000, LocalDateTime.of(2026, 1, 1, 8, 0));
        badgeService.evaluateOnActivity(userId, 5000, LocalDateTime.of(2026, 1, 2, 8, 0));

        Long count = userBadgeMapper.selectCount(new LambdaQueryWrapper<UserBadge>()
                .eq(UserBadge::getUserId, userId)
                .eq(UserBadge::getBadgeId, distanceBadge.getId()));
        assertEquals(1L, count);
    }

    @Test
    void streak_consecutiveDaysIncrement() {
        Long userId = register("13500000003");
        Badge streakBadge = insertBadge("streak_2", "streak_days", 2);

        badgeService.evaluateOnActivity(userId, 1000, LocalDateTime.of(2026, 1, 1, 8, 0));
        badgeService.evaluateOnActivity(userId, 1000, LocalDateTime.of(2026, 1, 2, 8, 0));

        UserStats stats = userStatsMapper.selectById(userId);
        assertEquals(2, stats.getStreakDays());
        assertTrue(hasBadge(userId, streakBadge.getId()));
    }

    @Test
    void streak_lateUpload_doesNotDecrease() {
        Long userId = register("13500000004");

        badgeService.evaluateOnActivity(userId, 1000, LocalDateTime.of(2026, 1, 1, 8, 0));
        badgeService.evaluateOnActivity(userId, 1000, LocalDateTime.of(2026, 1, 2, 8, 0));
        // 补录 1 月 1 日的记录，不应让连击从 2 回退
        badgeService.evaluateOnActivity(userId, 1000, LocalDateTime.of(2026, 1, 1, 20, 0));

        UserStats stats = userStatsMapper.selectById(userId);
        assertEquals(2, stats.getStreakDays());
        assertEquals(LocalDate.of(2026, 1, 2), stats.getLastActivityDate());
    }

    @Test
    void checkWeeklyGoals_awardsWeeklyGoalBadge() {
        Long userId = register("13500000005");
        LocalDate today = LocalDate.now(ZONE);

        UserGoal goal = new UserGoal();
        goal.setUserId(userId);
        goal.setPeriodType("weekly");
        goal.setTargetDistanceMeters(10000);
        goal.setCurrentDistanceMeters(12000);
        goal.setStartDate(today.minusDays(10));
        goal.setEndDate(today.minusDays(1));
        goal.setStatus(GoalStatus.ACTIVE.getCode());
        goalMapper.insert(goal);

        Badge weeklyBadge = insertBadge("weekly_1", "weekly_goal_complete", 1);

        badgeService.checkWeeklyGoals();

        assertEquals(GoalStatus.COMPLETED.getCode(), goalMapper.selectById(goal.getId()).getStatus());
        assertTrue(hasBadge(userId, weeklyBadge.getId()));
    }
}
