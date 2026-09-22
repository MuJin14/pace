package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.dto.response.MyRankResponse;

import java.time.LocalDateTime;

public interface LeaderboardService {

    void recordActivity(Long userId, int distanceMeters, LocalDateTime startTime, int activityType);

    PageResponse<LeaderboardEntryResponse> getBoard(String scope, String period, Integer type, long page, long size);

    MyRankResponse getMyRank(String scope, String period, Integer type, Long userId);

    void rebuildRolling30d();

    void cleanupExpired();
}
