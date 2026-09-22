package com.campusrun.server.task;

import com.campusrun.server.service.BadgeService;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@Profile("!test")
public class BadgeScheduler {

    private final BadgeService badgeService;

    public BadgeScheduler(BadgeService badgeService) {
        this.badgeService = badgeService;
    }

    @Scheduled(cron = "0 10 0 * * ?")
    public void resetStreaks() {
        badgeService.resetStreaks();
    }

    @Scheduled(cron = "0 30 0 * * MON")
    public void checkWeeklyGoals() {
        badgeService.checkWeeklyGoals();
    }
}
