package com.campusrun.server.enums;

public enum LeaderboardScope {

    DAILY("daily"),
    WEEKLY("weekly"),
    ROLLING_30D("rolling30d"),
    MONTHLY("monthly");

    private final String code;

    LeaderboardScope(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }

    public static LeaderboardScope fromCode(String code) {
        if (code == null) {
            return null;
        }
        for (LeaderboardScope scope : values()) {
            if (scope.code.equals(code)) {
                return scope;
            }
        }
        return null;
    }
}
