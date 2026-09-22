package com.campusrun.server.task;

import com.campusrun.server.service.GoalService;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@Profile("!test")
public class GoalScheduler {

    private final GoalService goalService;

    public GoalScheduler(GoalService goalService) {
        this.goalService = goalService;
    }

    @Scheduled(cron = "0 5 0 * * ?")
    public void expireOutdated() {
        goalService.expireOutdated();
    }
}
