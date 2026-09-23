package com.campusrun.server.event;

import com.campusrun.server.dto.websocket.FriendAcceptedPushData;

/**
 * 好友申请已被接受，推送给原申请方。
 */
public class FriendAcceptedEvent {

    private final Long targetUserId;
    private final FriendAcceptedPushData data;

    public FriendAcceptedEvent(Long targetUserId, FriendAcceptedPushData data) {
        this.targetUserId = targetUserId;
        this.data = data;
    }

    public Long getTargetUserId() {
        return targetUserId;
    }

    public FriendAcceptedPushData getData() {
        return data;
    }
}
