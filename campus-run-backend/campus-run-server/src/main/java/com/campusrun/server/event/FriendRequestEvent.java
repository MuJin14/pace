package com.campusrun.server.event;

import com.campusrun.server.dto.websocket.FriendRequestPushData;

/**
 * 好友申请已写入，推送给被申请人。
 */
public class FriendRequestEvent {

    private final Long targetUserId;
    private final FriendRequestPushData data;

    public FriendRequestEvent(Long targetUserId, FriendRequestPushData data) {
        this.targetUserId = targetUserId;
        this.data = data;
    }

    public Long getTargetUserId() {
        return targetUserId;
    }

    public FriendRequestPushData getData() {
        return data;
    }
}
