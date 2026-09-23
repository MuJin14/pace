package com.campusrun.server.dto.websocket;

/**
 * type = "friend_accepted" 的推送数据。
 */
public class FriendAcceptedPushData {

    private Long friendUserId;
    private String friendUniqueId;
    private String friendNickname;
    private String friendAvatarUrl;

    public Long getFriendUserId() {
        return friendUserId;
    }

    public void setFriendUserId(Long friendUserId) {
        this.friendUserId = friendUserId;
    }

    public String getFriendUniqueId() {
        return friendUniqueId;
    }

    public void setFriendUniqueId(String friendUniqueId) {
        this.friendUniqueId = friendUniqueId;
    }

    public String getFriendNickname() {
        return friendNickname;
    }

    public void setFriendNickname(String friendNickname) {
        this.friendNickname = friendNickname;
    }

    public String getFriendAvatarUrl() {
        return friendAvatarUrl;
    }

    public void setFriendAvatarUrl(String friendAvatarUrl) {
        this.friendAvatarUrl = friendAvatarUrl;
    }
}
