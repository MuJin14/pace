package com.campusrun.server.enums;

public enum GoalStatus {

    ACTIVE(0),
    COMPLETED(1),
    EXPIRED(2),
    CANCELLED(3);

    private final int code;

    GoalStatus(int code) {
        this.code = code;
    }

    public int getCode() {
        return code;
    }

    public static GoalStatus fromCode(int code) {
        for (GoalStatus status : values()) {
            if (status.code == code) {
                return status;
            }
        }
        return null;
    }
}
