package com.campusrun.server.service;

import com.campusrun.server.dto.request.GoalCreateRequest;
import com.campusrun.server.dto.response.GoalResponse;

import java.time.LocalDateTime;
import java.util.List;

public interface GoalService {

    GoalResponse create(Long userId, GoalCreateRequest request);

    List<GoalResponse> list(Long userId);

    GoalResponse get(Long userId, Long goalId);

    void cancel(Long userId, Long goalId);

    void addProgress(Long userId, int distanceMeters, LocalDateTime startTime);

    void expireOutdated();
}
