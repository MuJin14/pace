package com.campusrun.server.task;

import com.campusrun.server.service.LeaderboardService;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class LeaderboardScheduler {

    private final LeaderboardService leaderboardService;

    public LeaderboardScheduler(LeaderboardService leaderboardService) {
        this.leaderboardService = leaderboardService;
    }

    @Scheduled(cron = "0 0 3 * * ?")
    public void rebuildRolling30d() {
        leaderboardService.rebuildRolling30d();
    }

    @Scheduled(cron = "0 0 4 * * ?")
    public void cleanupExpired() {
        leaderboardService.cleanupExpired();
    }
}
