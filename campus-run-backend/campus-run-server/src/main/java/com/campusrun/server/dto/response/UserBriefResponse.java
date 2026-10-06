package com.campusrun.server.dto.response;

public class UserBriefResponse {

    private Long userId;
    private String uniqueId;
    private String nickname;
    private String avatarUrl;

    /**
     * 与当前登录用户的关系（self / friend / pending_outgoing / pending_incoming / none）。
     * 客户端据此决定按钮：自己→看主页、好友→发消息、待通过→通过验证、无关系→添加好友。
     */
    private String relation;

    public String getRelation() {
        return relation;
    }

    public void setRelation(String relation) {
        this.relation = relation;
    }

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

    public String getAvatarUrl() {
        return avatarUrl;
    }

    public void setAvatarUrl(String avatarUrl) {
        this.avatarUrl = avatarUrl;
    }
}
