package com.campusrun.server.dto.response;

import java.time.LocalDateTime;

/**
 * 用户主页（查看任意用户，类似微信的个人资料页）。
 *
 * <p>只暴露「社交上必要」的字段：昵称、专属 ID、头像、加入时间、运动汇总。
 * **不含手机号**——手机号只在「我的」页对自己可见，不应因为搜到一个人就泄露。
 *
 * <p><b>性别 / 年龄按用户自己的可见性设置返回</b>：
 * 本人访问时总是返回真实值（自己的设置页要回显）；
 * 他人访问时，只有对应 {@code *Public = 1} 才返回，否则字段为 {@code null}。
 * 这样「不公开」在协议层就是不存在的字段，前端不需要额外判断，也避免数据被客户端推断出来。
 */
public class UserProfileResponse {

    private Long userId;
    private String uniqueId;
    private String nickname;
    private String avatarUrl;
    private LocalDateTime createdAt;

    /**
     * 性别：0=保密 1=男 2=女。
     * 仅当「本人访问」或「对方设置了 genderPublic」时才非 null。
     */
    private Integer gender;
    /**
     * 年龄。仅当「本人访问」或「对方设置了 agePublic」时才非 null。
     */
    private Integer age;

    /** 当前登录用户与 TA 的关系，见 {@code UserRelation}。前端据此决定操作按钮。 */
    private String relation;

    /** 累计距离（米）。 */
    private Integer totalDistanceMeters;
    /** 累计运动次数。 */
    private Integer totalActivityCount;
    /** 连续打卡天数。 */
    private Integer streakDays;

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

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public String getRelation() {
        return relation;
    }

    public void setRelation(String relation) {
        this.relation = relation;
    }

    public Integer getTotalDistanceMeters() {
        return totalDistanceMeters;
    }

    public void setTotalDistanceMeters(Integer totalDistanceMeters) {
        this.totalDistanceMeters = totalDistanceMeters;
    }

    public Integer getTotalActivityCount() {
        return totalActivityCount;
    }

    public void setTotalActivityCount(Integer totalActivityCount) {
        this.totalActivityCount = totalActivityCount;
    }

    public Integer getStreakDays() {
        return streakDays;
    }

    public void setStreakDays(Integer streakDays) {
        this.streakDays = streakDays;
    }

    public Integer getGender() {
        return gender;
    }

    public void setGender(Integer gender) {
        this.gender = gender;
    }

    public Integer getAge() {
        return age;
    }

    public void setAge(Integer age) {
        this.age = age;
    }
}
