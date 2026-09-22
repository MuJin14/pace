package com.campusrun.server.enums;

public enum GoalPeriodType {

    WEEKLY("weekly"),
    MONTHLY("monthly"),
    CUSTOM("custom");

    private final String code;

    GoalPeriodType(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }

    public static GoalPeriodType fromCode(String code) {
        if (code == null) {
            return null;
        }
        for (GoalPeriodType type : values()) {
            if (type.code.equals(code)) {
                return type;
            }
        }
        return null;
    }
}
