package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.dto.response.MyRankResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.LeaderboardService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/leaderboard")
public class LeaderboardController {

    private final LeaderboardService leaderboardService;

    public LeaderboardController(LeaderboardService leaderboardService) {
        this.leaderboardService = leaderboardService;
    }

    @GetMapping
    public Result<PageResponse<LeaderboardEntryResponse>> board(
            @RequestParam(required = false) String scope,
            @RequestParam(required = false) String period,
            @RequestParam(required = false) Integer type,
            @RequestParam(defaultValue = "1") long page,
            @RequestParam(defaultValue = "20") long size) {
        return Result.success(leaderboardService.getBoard(scope, period, type, page, size));
    }

    @GetMapping("/my-rank")
    public Result<MyRankResponse> myRank(
            @RequestParam(required = false) String scope,
            @RequestParam(required = false) String period,
            @RequestParam(required = false) Integer type) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(leaderboardService.getMyRank(scope, period, type, userId));
    }
}
