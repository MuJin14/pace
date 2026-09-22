package com.campusrun.server.enums;

public enum FriendshipStatus {

    PENDING(0),
    ACCEPTED(1);

    private final int code;

    FriendshipStatus(int code) {
        this.code = code;
    }

    public int getCode() {
        return code;
    }

    public static FriendshipStatus fromCode(int code) {
        for (FriendshipStatus status : values()) {
            if (status.code == code) {
                return status;
            }
        }
        return null;
    }
}
