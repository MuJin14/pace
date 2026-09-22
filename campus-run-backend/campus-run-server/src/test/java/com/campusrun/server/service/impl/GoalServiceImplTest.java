package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.GoalCreateRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.GoalResponse;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.UserGoal;
import com.campusrun.server.enums.GoalStatus;
import com.campusrun.server.mapper.UserGoalMapper;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.GoalService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class GoalServiceImplTest {

    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private GoalService goalService;

    @Autowired
    private AuthService authService;

    @Autowired
    private UserGoalMapper goalMapper;

    private Long register(String phone) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname("跑者" + phone.substring(phone.length() - 4));
        LoginResponse resp = authService.register(req);
        return resp.getUserId();
    }

    private GoalCreateRequest weeklyRequest(LocalDate monday, int target) {
        GoalCreateRequest req = new GoalCreateRequest();
        req.setPeriodType("weekly");
        req.setTargetDistanceMeters(target);
        req.setStartDate(monday);
        req.setEndDate(monday.plusDays(6));
        return req;
    }

    @Test
    void create_success() {
        Long userId = register("13700000001");
        LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);

        GoalResponse created = goalService.create(userId, weeklyRequest(monday, 10000));

        assertNotNull(created.getId());
        assertEquals("weekly", created.getPeriodType());
        assertEquals(0, created.getCurrentDistanceMeters());
        assertEquals(GoalStatus.ACTIVE.getCode(), created.getStatus());
    }

    @Test
    void create_duplicateWeeklyActive_throws() {
        Long userId = register("13700000002");
        LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);
        goalService.create(userId, weeklyRequest(monday, 10000));

        BusinessException ex = assertThrows(BusinessException.class,
                () -> goalService.create(userId, weeklyRequest(monday, 20000)));
        assertEquals(ErrorCode.GOAL_EXISTS.getCode(), ex.getCode());
    }

    @Test
    void create_differentPeriodType_allowed() {
        Long userId = register("13700000003");
        LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);
        goalService.create(userId, weeklyRequest(monday, 10000));

        GoalCreateRequest monthly = new GoalCreateRequest();
        monthly.setPeriodType("monthly");
        monthly.setTargetDistanceMeters(50000);
        monthly.setStartDate(LocalDate.now(ZONE).withDayOfMonth(1));
        monthly.setEndDate(LocalDate.now(ZONE).withDayOfMonth(LocalDate.now(ZONE).lengthOfMonth()));

        GoalResponse created = goalService.create(userId, monthly);
        assertEquals("monthly", created.getPeriodType());
    }

    @Test
    void cancel_thenRecreate() {
        Long userId = register("13700000004");
        LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);
        GoalResponse created = goalService.create(userId, weeklyRequest(monday, 10000));

        goalService.cancel(userId, created.getId());
        UserGoal cancelled = goalMapper.selectById(created.getId());
        assertEquals(GoalStatus.CANCELLED.getCode(), cancelled.getStatus());

        GoalResponse recreated = goalService.create(userId, weeklyRequest(monday, 20000));
        assertNotNull(recreated.getId());
    }

    @Test
    void addProgress_lateUpload_matchesCorrectPeriod() {
        Long userId = register("13700000005");
        LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);
        GoalResponse goal = goalService.create(userId, weeklyRequest(monday, 10000));

        // 本周内的运动（即便是迟到的上传，只要 startTime 落本周）→ 累加
        LocalDateTime inWeek = monday.plusDays(2).atStartOfDay();
        goalService.addProgress(userId, 3000, inWeek);

        // 上一周的运动（startTime 不在本周）→ 不累加
        LocalDateTime lastWeek = monday.minusWeeks(1).plusDays(2).atStartOfDay();
        goalService.addProgress(userId, 5000, lastWeek);

        UserGoal updated = goalMapper.selectById(goal.getId());
        assertEquals(3000, updated.getCurrentDistanceMeters());
    }

    @Test
    void expireOutdated_completedAndExpired() {
        Long userId = register("13700000006");
        LocalDate today = LocalDate.now(ZONE);

        UserGoal reached = new UserGoal();
        reached.setUserId(userId);
        reached.setPeriodType("weekly");
        reached.setTargetDistanceMeters(10000);
        reached.setCurrentDistanceMeters(12000);
        reached.setStartDate(today.minusDays(10));
        reached.setEndDate(today.minusDays(1));
        reached.setStatus(GoalStatus.ACTIVE.getCode());
        goalMapper.insert(reached);

        UserGoal missed = new UserGoal();
        missed.setUserId(userId);
        missed.setPeriodType("weekly");
        missed.setTargetDistanceMeters(10000);
        missed.setCurrentDistanceMeters(5000);
        missed.setStartDate(today.minusDays(10));
        missed.setEndDate(today.minusDays(1));
        missed.setStatus(GoalStatus.ACTIVE.getCode());
        goalMapper.insert(missed);

        goalService.expireOutdated();

        assertEquals(GoalStatus.COMPLETED.getCode(), goalMapper.selectById(reached.getId()).getStatus());
        assertEquals(GoalStatus.EXPIRED.getCode(), goalMapper.selectById(missed.getId()).getStatus());
    }
}
