package com.campusrun.server.task;

import com.campusrun.server.service.GoalService;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@Profile("!test")
public class GoalScheduler {

    private final GoalService goalService;
    private final ScheduledJobLockService jobLock;

    public GoalScheduler(GoalService goalService, ScheduledJobLockService jobLock) {
        this.goalService = goalService;
        this.jobLock = jobLock;
    }

    @Scheduled(cron = "0 5 0 * * ?")
    public void expireOutdated() {
        // 多实例下若不互斥，过期目标会被重复结算（重复置为 COMPLETED/EXPIRED）。
        if (!jobLock.tryAcquireToday("goal.expireOutdated")) {
            return;
        }
        goalService.expireOutdated();
    }
}
