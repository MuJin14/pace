package com.campusrun.server.security;

import com.campusrun.server.enums.UserRole;

public class LoginUser {

    private final Long userId;
    private final String uniqueId;
    private final Integer role;

    public LoginUser(Long userId, String uniqueId) {
        this(userId, uniqueId, UserRole.USER.getCode());
    }

    public LoginUser(Long userId, String uniqueId, Integer role) {
        this.userId = userId;
        this.uniqueId = uniqueId;
        this.role = role;
    }

    public Long getUserId() {
        return userId;
    }

    public String getUniqueId() {
        return uniqueId;
    }

    public Integer getRole() {
        return role;
    }
}
