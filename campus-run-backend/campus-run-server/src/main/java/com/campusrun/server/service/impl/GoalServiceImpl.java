package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.GoalCreateRequest;
import com.campusrun.server.dto.response.GoalResponse;
import com.campusrun.server.entity.UserGoal;
import com.campusrun.server.enums.GoalPeriodType;
import com.campusrun.server.enums.GoalStatus;
import com.campusrun.server.mapper.UserGoalMapper;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.GoalService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

@Service
public class GoalServiceImpl implements GoalService {

    private static final Logger log = LoggerFactory.getLogger(GoalServiceImpl.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final UserGoalMapper goalMapper;
    private final UserMapper userMapper;

    public GoalServiceImpl(UserGoalMapper goalMapper, UserMapper userMapper) {
        this.goalMapper = goalMapper;
        this.userMapper = userMapper;
    }

    @Override
    @Transactional
    public GoalResponse create(Long userId, GoalCreateRequest request) {
        GoalPeriodType periodType = GoalPeriodType.fromCode(request.getPeriodType());
        if (periodType == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "周期类型不合法");
        }

        // weekly/monthly 的周期日期由服务端按 Asia/Shanghai 推导，客户端传值一律忽略；
        // 只有 custom 才使用客户端日期。推导结果必须与 addProgress 的周期匹配语义一致
        // （addProgress 用活动日期所在周的周一 / 当月 1 日作为 periodKey 与 [startDate, endDate] 比较）。
        LocalDate startDate;
        LocalDate endDate;
        switch (periodType) {
            case WEEKLY -> {
                LocalDate monday = LocalDate.now(ZONE).with(DayOfWeek.MONDAY);
                startDate = monday;
                endDate = monday.plusDays(6);
            }
            case MONTHLY -> {
                LocalDate today = LocalDate.now(ZONE);
                startDate = today.withDayOfMonth(1);
                endDate = today.withDayOfMonth(today.lengthOfMonth());
            }
            case CUSTOM -> {
                startDate = request.getStartDate();
                endDate = request.getEndDate();
                if (startDate == null || endDate == null) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "custom 周期必须指定开始与结束日期");
                }
                if (endDate.isBefore(startDate)) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "结束日期必须不早于开始日期");
                }
            }
            default -> throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "周期类型不合法");
        }

        // 悲观锁锁住用户行，避免并发下「先查后插」失效
        userMapper.lockUserForUpdate(userId);

        Long existing = goalMapper.selectCount(new LambdaQueryWrapper<UserGoal>()
                .eq(UserGoal::getUserId, userId)
                .eq(UserGoal::getPeriodType, periodType.getCode())
                .eq(UserGoal::getStatus, GoalStatus.ACTIVE.getCode()));
        if (existing != null && existing > 0) {
            throw new BusinessException(ErrorCode.GOAL_EXISTS);
        }

        UserGoal goal = new UserGoal();
        goal.setUserId(userId);
        goal.setPeriodType(periodType.getCode());
        goal.setTargetDistanceMeters(request.getTargetDistanceMeters());
        goal.setCurrentDistanceMeters(0);
        goal.setStartDate(startDate);
        goal.setEndDate(endDate);
        goal.setStatus(GoalStatus.ACTIVE.getCode());
        goalMapper.insert(goal);
        return toResponse(goal);
    }

    @Override
    public List<GoalResponse> list(Long userId) {
        List<UserGoal> goals = goalMapper.selectList(new LambdaQueryWrapper<UserGoal>()
                .eq(UserGoal::getUserId, userId)
                .orderByDesc(UserGoal::getId));
        return goals.stream().map(this::toResponse).toList();
    }

    @Override
    public GoalResponse get(Long userId, Long goalId) {
        UserGoal goal = goalMapper.selectById(goalId);
        if (goal == null || !goal.getUserId().equals(userId)) {
            throw new BusinessException(ErrorCode.GOAL_NOT_FOUND);
        }
        return toResponse(goal);
    }

    @Override
    @Transactional
    public void cancel(Long userId, Long goalId) {
        UserGoal goal = goalMapper.selectById(goalId);
        if (goal == null || !goal.getUserId().equals(userId)) {
            throw new BusinessException(ErrorCode.GOAL_NOT_FOUND);
        }
        if (goal.getStatus() != GoalStatus.ACTIVE.getCode()) {
            throw new BusinessException(ErrorCode.GOAL_INVALID);
        }
        goal.setStatus(GoalStatus.CANCELLED.getCode());
        goalMapper.updateById(goal);
    }

    /**
     * 按 startTime 匹配每个进行中目标的所属周期，命中才累加进度。
     */
    @Override
    public void addProgress(Long userId, int distanceMeters, LocalDateTime startTime) {
        List<UserGoal> activeGoals = goalMapper.selectList(new LambdaQueryWrapper<UserGoal>()
                .eq(UserGoal::getUserId, userId)
                .eq(UserGoal::getStatus, GoalStatus.ACTIVE.getCode()));
        if (activeGoals.isEmpty()) {
            return;
        }

        LocalDate activityDate = startTime.atZone(ZONE).toLocalDate();
        for (UserGoal goal : activeGoals) {
            GoalPeriodType periodType = GoalPeriodType.fromCode(goal.getPeriodType());
            if (periodType == null) {
                continue;
            }
            LocalDate periodKey = switch (periodType) {
                case WEEKLY -> activityDate.with(DayOfWeek.MONDAY);
                case MONTHLY -> activityDate.withDayOfMonth(1);
                case CUSTOM -> activityDate;
            };
            if (periodKey.isBefore(goal.getStartDate()) || periodKey.isAfter(goal.getEndDate())) {
                continue;
            }
            goalMapper.addProgress(goal.getId(), distanceMeters);
            int newProgress = (goal.getCurrentDistanceMeters() == null ? 0 : goal.getCurrentDistanceMeters())
                    + distanceMeters;
            log.info("更新目标进度，userId={}, goalId={}, addedDistance={}, newProgress={}",
                    userId, goal.getId(), distanceMeters, newProgress);
        }
    }

    @Override
    @Transactional
    public void expireOutdated() {
        log.info("定时任务开始：expireOutdated");
        long start = System.currentTimeMillis();
        LocalDate today = LocalDate.now(ZONE);
        List<UserGoal> outdated = goalMapper.selectList(new LambdaQueryWrapper<UserGoal>()
                .eq(UserGoal::getStatus, GoalStatus.ACTIVE.getCode())
                .lt(UserGoal::getEndDate, today));
        for (UserGoal goal : outdated) {
            if (goal.getCurrentDistanceMeters() >= goal.getTargetDistanceMeters()) {
                goal.setStatus(GoalStatus.COMPLETED.getCode());
            } else {
                goal.setStatus(GoalStatus.EXPIRED.getCode());
            }
            goalMapper.updateById(goal);
        }
        log.info("定时任务完成：expireOutdated, count={}, costMs={}",
                outdated.size(), System.currentTimeMillis() - start);
    }

    private GoalResponse toResponse(UserGoal goal) {
        GoalResponse response = new GoalResponse();
        response.setId(goal.getId());
        response.setPeriodType(goal.getPeriodType());
        response.setTargetDistanceMeters(goal.getTargetDistanceMeters());
        response.setCurrentDistanceMeters(goal.getCurrentDistanceMeters());
        response.setStartDate(goal.getStartDate());
        response.setEndDate(goal.getEndDate());
        response.setStatus(goal.getStatus());
        response.setCreatedAt(goal.getCreatedAt());
        return response;
    }
}
