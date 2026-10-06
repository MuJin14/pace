package com.campusrun.server.dto.response;

import java.time.LocalDateTime;

/**
 * 管理后台的用户列表项。
 *
 * <p>**刻意不返回密码哈希**（哪怕管理员也不该看到）。
 * 管理员需要的是「找到人 + 重置密码」，不是拿到口令。
 */
public class AdminUserItem {

    private Long userId;
    private String uniqueId;
    private String nickname;
    private String phone;
    private String avatarUrl;
    private Integer role;
    private LocalDateTime createdAt;

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public String getUniqueId() {
        return uniqueId;
    }

    public void setUniqueId(String uniqueId) {
        this.uniqueId = uniqueId;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getAvatarUrl() {
        return avatarUrl;
    }

    public void setAvatarUrl(String avatarUrl) {
        this.avatarUrl = avatarUrl;
    }

    public Integer getRole() {
        return role;
    }

    public void setRole(Integer role) {
        this.role = role;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
