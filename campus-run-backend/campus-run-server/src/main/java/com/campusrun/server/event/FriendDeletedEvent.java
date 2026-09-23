package com.campusrun.server.event;

import com.campusrun.server.dto.websocket.FriendDeletedPushData;

/**
 * 好友关系被删除，推送给被删除方。
 */
public class FriendDeletedEvent {

    private final Long targetUserId;
    private final FriendDeletedPushData data;

    public FriendDeletedEvent(Long targetUserId, FriendDeletedPushData data) {
        this.targetUserId = targetUserId;
        this.data = data;
    }

    public Long getTargetUserId() {
        return targetUserId;
    }

    public FriendDeletedPushData getData() {
        return data;
    }
}
