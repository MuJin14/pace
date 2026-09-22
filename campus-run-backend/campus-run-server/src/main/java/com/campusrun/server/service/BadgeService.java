package com.campusrun.server.service;

import com.campusrun.server.dto.response.BadgeResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;

import java.time.LocalDateTime;
import java.util.List;

public interface BadgeService {

    List<BadgeResponse> listAll(Long userId);

    List<UserBadgeResponse> listMine(Long userId);

    void evaluateOnActivity(Long userId, int distanceMeters, LocalDateTime startTime);

    void resetStreaks();

    void checkWeeklyGoals();
}
