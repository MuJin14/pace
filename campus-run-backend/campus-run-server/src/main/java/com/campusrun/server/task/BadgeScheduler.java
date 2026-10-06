package com.campusrun.server.task;

import com.campusrun.server.service.BadgeService;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@Profile("!test")
public class BadgeScheduler {

    private final BadgeService badgeService;
    private final ScheduledJobLockService jobLock;

    public BadgeScheduler(BadgeService badgeService, ScheduledJobLockService jobLock) {
        this.badgeService = badgeService;
        this.jobLock = jobLock;
    }

    @Scheduled(cron = "0 10 0 * * ?")
    public void resetStreaks() {
        // 多实例下若不互斥，连续打卡天数会被重复重置。
        if (!jobLock.tryAcquireToday("badge.resetStreaks")) {
            return;
        }
        badgeService.resetStreaks();
    }

    @Scheduled(cron = "0 30 0 * * MON")
    public void checkWeeklyGoals() {
        // 每周一触发，但锁按「日期」维度：同一天多实例只跑一次即可。
        if (!jobLock.tryAcquireToday("badge.checkWeeklyGoals")) {
            return;
        }
        badgeService.checkWeeklyGoals();
    }
}
