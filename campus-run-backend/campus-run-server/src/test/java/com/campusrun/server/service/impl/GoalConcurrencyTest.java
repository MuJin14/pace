package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.GoalCreateRequest;
import com.campusrun.server.dto.request.RegisterRequest;
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

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;

@SpringBootTest
@ActiveProfiles("test")
class GoalConcurrencyTest {

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
        req.setNickname("并发" + phone.substring(phone.length() - 4));
        LoginResponse resp = authService.register(req);
        return resp.getUserId();
    }

    @Test
    void createWeeklyGoal_concurrent_safe() throws Exception {
        Long userId = register("13600000001");
        LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);

        GoalCreateRequest req = new GoalCreateRequest();
        req.setPeriodType("weekly");
        req.setTargetDistanceMeters(10000);
        req.setStartDate(monday);
        req.setEndDate(monday.plusDays(6));

        int threads = 2;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch ready = new CountDownLatch(threads);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<Object>> futures = new ArrayList<>();

        for (int i = 0; i < threads; i++) {
            futures.add(pool.submit(() -> {
                ready.countDown();
                start.await();
                try {
                    goalService.create(userId, req);
                    return "OK";
                } catch (BusinessException e) {
                    return e.getCode();
                }
            }));
        }
        ready.await();
        start.countDown();

        Set<Object> results = new HashSet<>();
        for (Future<Object> future : futures) {
            results.add(future.get(30, TimeUnit.SECONDS));
        }
        pool.shutdown();

        assertEquals(Set.of("OK", ErrorCode.GOAL_EXISTS.getCode()), results);

        Long activeCount = goalMapper.selectCount(new LambdaQueryWrapper<UserGoal>()
                .eq(UserGoal::getUserId, userId)
                .eq(UserGoal::getPeriodType, "weekly")
                .eq(UserGoal::getStatus, GoalStatus.ACTIVE.getCode()));
        assertEquals(1L, activeCount);
    }
}
