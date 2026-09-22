package com.campusrun.server.enums;

public enum BadgeRuleType {

    TOTAL_DISTANCE("total_distance"),
    ACTIVITY_COUNT("activity_count"),
    STREAK_DAYS("streak_days"),
    WEEKLY_GOAL_COMPLETE("weekly_goal_complete");

    private final String code;

    BadgeRuleType(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }

    public static BadgeRuleType fromCode(String code) {
        if (code == null) {
            return null;
        }
        for (BadgeRuleType type : values()) {
            if (type.code.equals(code)) {
                return type;
            }
        }
        return null;
    }
}
