package com.campusrun.server.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

import java.time.LocalDateTime;

@TableName("user")
public class User {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String uniqueId;
    private String phone;
    private String passwordHash;
    private String nickname;
    private String avatarUrl;
    /** 性别：0=保密 1=男 2=女；null=未填写。 */
    private Integer gender;
    /** 年龄 1-120；null=未填写。 */
    private Integer age;
    /**
     * 性别是否对他人公开。
     *
     * <p>默认 0（不公开）—— 隐私默认关闭，必须由用户主动开启，
     * 而不是注册时默认公开。这是产品与合规的共同要求。
     */
    private Integer genderPublic;
    /** 年龄是否对他人公开。默认 0（不公开）。 */
    private Integer agePublic;
    /**
     * 令牌失效时间：改密时写入当前时间。
     *
     * <p>签发时间早于该值的 refresh token 一律拒绝。
     * 没有这个字段的话，改密只能拦住「用新密码登录」，
     * 而别人手里那张 30 天有效的 refresh token 仍能不断换到新 access token —— 等于没改。
     */
    private LocalDateTime tokenInvalidBefore;

    /**
     * 令牌版本：递增即让该用户**所有**已签发的 access/refresh token 立即失效。
     *
     * <p>为什么不复用 {@link #tokenInvalidBefore}：JWT 的 {@code iat} 只有秒级精度，
     * 而 {@code tokenInvalidBefore} 带毫秒 —— 两者比较必须放宽成
     * {@code isBefore} 才不会误杀刚签发的新令牌（见 AuthServiceImpl 的说明），
     * 于是「同一秒内签发的旧令牌」会有约 1 秒的存活窗口。
     *
     * <p>版本号是精确比较（不相等即失效），没有这个边界问题；
     * 而且「踢下线」就是一次自增，不需要处理时间与时区。
     *
     * <p>默认 0：迁移时已有用户都是 0，他们手上的旧令牌里没有 ver claim，
     * 校验时按 0 处理，因此**不会被这次改动强制下线**。
     */
    private Integer tokenVersion;

    /**
     * 最近一次登录的设备标识。
     *
     * <p>只用来判断「这次登录是不是换了一台设备」——
     * 相同就不递增 {@link #tokenVersion}，否则用户杀掉 App 重进
     * 就会把自己踢下线（最正常的操作被判成异常）。
     *
     * <p>存的是客户端自己生成的随机串（卸载前持久），不是硬件 ID：
     * 我们不需要跨安装识别同一台手机，只要能区分「两个并存的登录」就够了。
     */
    private String deviceId;

    private Integer role;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getUniqueId() {
        return uniqueId;
    }

    public void setUniqueId(String uniqueId) {
        this.uniqueId = uniqueId;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
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

    public Integer getRole() {
        return role;
    }

    public void setRole(Integer role) {
        this.role = role;
    }

    public Integer getTokenVersion() {
        return tokenVersion == null ? 0 : tokenVersion;
    }

    public void setTokenVersion(Integer tokenVersion) {
        this.tokenVersion = tokenVersion;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
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

    public Integer getGenderPublic() {
        return genderPublic;
    }

    public void setGenderPublic(Integer genderPublic) {
        this.genderPublic = genderPublic;
    }

    public Integer getAgePublic() {
        return agePublic;
    }

    public void setAgePublic(Integer agePublic) {
        this.agePublic = agePublic;
    }

    public LocalDateTime getTokenInvalidBefore() {
        return tokenInvalidBefore;
    }

    public void setTokenInvalidBefore(LocalDateTime tokenInvalidBefore) {
        this.tokenInvalidBefore = tokenInvalidBefore;
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
