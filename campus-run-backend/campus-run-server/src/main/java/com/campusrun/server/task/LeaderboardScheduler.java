package com.campusrun.server.task;

import com.campusrun.server.service.LeaderboardService;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

@Component
@Profile("!test")
public class LeaderboardScheduler {

    private final LeaderboardService leaderboardService;
    private final ScheduledJobLockService jobLock;

    public LeaderboardScheduler(LeaderboardService leaderboardService,
                                ScheduledJobLockService jobLock) {
        this.leaderboardService = leaderboardService;
        this.jobLock = jobLock;
    }

    @Scheduled(cron = "0 0 3 * * ?")
    public void rebuildRolling30d() {
        // 多实例部署时此任务会在每个实例触发；用数据库锁保证当天只被一个实例执行，
        // 否则滚动 30 天榜会被重复累加。
        if (!jobLock.tryAcquireToday("leaderboard.rebuildRolling30d")) {
            return;
        }
        leaderboardService.rebuildRolling30d();
    }

    @Scheduled(cron = "0 0 4 * * ?")
    public void cleanupExpired() {
        if (!jobLock.tryAcquireToday("leaderboard.cleanupExpired")) {
            return;
        }
        leaderboardService.cleanupExpired();
        // 顺带清理过期的任务锁记录，避免锁表无限增长（保留最近 30 天便于排查）。
        jobLock.purgeBefore(LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).minusDays(30));
    }
}
