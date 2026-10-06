package com.campusrun.server.dto.response;

public class LeaderboardEntryResponse {

    private Long rank;
    private Long userId;
    private String uniqueId;
    private String nickname;
    private String avatarUrl;
    private Integer distanceMeters;

    /**
     * 当前登录用户与 TA 的关系（self / friend / pending_outgoing / pending_incoming / none）。
     *
     * <p>排行榜是主要的社交入口：用户看到榜上的人想直接加好友。
     * 由服务端算 relation，前端才能正确显示「添加好友 / 已是好友 / 通过验证」，
     * 而不是点了才发现「已是好友」或「申请已存在」。
     */
    private String relation;

    /**
     * 与**上一名**的距离差（米）。第 1 名为 null。
     *
     * <p>这是「竞争感」的关键：只显示一个孤零零的总里程，用户不知道自己
     * 离前一名差多少、追不追得上。有了差额，榜单才有「可追赶」的目标感。
     */
    private Integer gapToAheadMeters;

    /**
     * 与**下一名**的距离差（米）。最后一名或无下一名时为 null。
     *
     * <p>用于「领先多少」提示：领先很多可激励，领先很少会促使加练。
     */
    private Integer gapToBehindMeters;

    public Long getRank() {
        return rank;
    }

    public void setRank(Long rank) {
        this.rank = rank;
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

    public Integer getDistanceMeters() {
        return distanceMeters;
    }

    public void setDistanceMeters(Integer distanceMeters) {
        this.distanceMeters = distanceMeters;
    }

    public String getRelation() {
        return relation;
    }

    public void setRelation(String relation) {
        this.relation = relation;
    }

    public Integer getGapToAheadMeters() {
        return gapToAheadMeters;
    }

    public void setGapToAheadMeters(Integer gapToAheadMeters) {
        this.gapToAheadMeters = gapToAheadMeters;
    }

    public Integer getGapToBehindMeters() {
        return gapToBehindMeters;
    }

    public void setGapToBehindMeters(Integer gapToBehindMeters) {
        this.gapToBehindMeters = gapToBehindMeters;
    }
}
