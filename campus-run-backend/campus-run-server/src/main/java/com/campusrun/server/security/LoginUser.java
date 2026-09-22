package com.campusrun.server.security;

public class LoginUser {

    private final Long userId;
    private final String uniqueId;

    public LoginUser(Long userId, String uniqueId) {
        this.userId = userId;
        this.uniqueId = uniqueId;
    }

    public Long getUserId() {
        return userId;
    }

    public String getUniqueId() {
        return uniqueId;
    }
}
