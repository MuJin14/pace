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
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

@Service
public class GoalServiceImpl implements GoalService {

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
        if (request.getEndDate().isBefore(request.getStartDate())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "结束日期必须不早于开始日期");
        }

        // 悲观锁锁住用户行，避免并发下「先查后插」失效
        userMapper.lockUserForUpdate(userId);

        Long existing = goalMapper.selectCount(new LambdaQueryWrapper<UserGoal>()
                .eq(UserGoal::getUserId, userId)
                .eq(UserGoal::getPeriodType, request.getPeriodType())
                .eq(UserGoal::getStatus, GoalStatus.ACTIVE.getCode()));
        if (existing != null && existing > 0) {
            throw new BusinessException(ErrorCode.GOAL_EXISTS);
        }

        UserGoal goal = new UserGoal();
        goal.setUserId(userId);
        goal.setPeriodType(periodType.getCode());
        goal.setTargetDistanceMeters(request.getTargetDistanceMeters());
        goal.setCurrentDistanceMeters(0);
        goal.setStartDate(request.getStartDate());
        goal.setEndDate(request.getEndDate());
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
        }
    }

    @Override
    @Transactional
    public void expireOutdated() {
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
