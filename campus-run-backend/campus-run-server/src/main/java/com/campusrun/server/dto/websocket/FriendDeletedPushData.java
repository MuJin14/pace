package com.campusrun.server.dto.websocket;

/**
 * type = "friend_deleted" 的推送数据。
 */
public class FriendDeletedPushData {

    private Long friendUserId;

    public Long getFriendUserId() {
        return friendUserId;
    }

    public void setFriendUserId(Long friendUserId) {
        this.friendUserId = friendUserId;
    }
}
