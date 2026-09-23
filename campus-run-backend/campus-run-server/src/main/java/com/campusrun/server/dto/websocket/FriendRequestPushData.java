package com.campusrun.server.dto.websocket;

import java.time.LocalDateTime;

/**
 * type = "friend_request" 的推送数据。
 */
public class FriendRequestPushData {

    private Long requestId;
    private Long fromUserId;
    private String fromUniqueId;
    private String fromNickname;
    private String fromAvatarUrl;
    private LocalDateTime createdAt;

    public Long getRequestId() {
        return requestId;
    }

    public void setRequestId(Long requestId) {
        this.requestId = requestId;
    }

    public Long getFromUserId() {
        return fromUserId;
    }

    public void setFromUserId(Long fromUserId) {
        this.fromUserId = fromUserId;
    }

    public String getFromUniqueId() {
        return fromUniqueId;
    }

    public void setFromUniqueId(String fromUniqueId) {
        this.fromUniqueId = fromUniqueId;
    }

    public String getFromNickname() {
        return fromNickname;
    }

    public void setFromNickname(String fromNickname) {
        this.fromNickname = fromNickname;
    }

    public String getFromAvatarUrl() {
        return fromAvatarUrl;
    }

    public void setFromAvatarUrl(String fromAvatarUrl) {
        this.fromAvatarUrl = fromAvatarUrl;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
