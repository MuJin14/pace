package com.campusrun.server.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

import java.time.LocalDateTime;

/**
 * 会话偏好（目前只有「免打扰」）。
 *
 * <p>按 {@code (user_id, friend_id)} 唯一：免打扰是**单向、按会话**的 ——
 * A 屏蔽 B 的消息提醒，不影响 B 是否接收 A 的提醒。
 * 这是微信等主流 IM 的语义，也避免了「一方设置影响双方」的争议。
 */
@TableName("chat_preference")
public class ChatPreference {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long userId;
    private Long friendId;

    /** 是否免打扰：0=否 1=是。 */
    private Integer muted;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public Long getFriendId() {
        return friendId;
    }

    public void setFriendId(Long friendId) {
        this.friendId = friendId;
    }

    public Integer getMuted() {
        return muted;
    }

    public void setMuted(Integer muted) {
        this.muted = muted;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
