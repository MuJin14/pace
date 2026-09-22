package com.campusrun.server.event;

import com.campusrun.server.entity.Badge;

public class BadgeAwardedEvent {

    private final Long userId;
    private final Badge badge;

    public BadgeAwardedEvent(Long userId, Badge badge) {
        this.userId = userId;
        this.badge = badge;
    }

    public Long getUserId() {
        return userId;
    }

    public Badge getBadge() {
        return badge;
    }
}
