package com.campusrun.server.dto.response;

import java.time.LocalDateTime;

public class UserInfoResponse {

    private Long userId;
    private String uniqueId;
    private String nickname;
    private String phone;
    private String avatarUrl;
    /** 性别：0=保密 1=男 2=女；null=未填写（仅对自己可见的原始值）。 */
    private Integer gender;
    /** 年龄；null=未填写。 */
    private Integer age;
    /** 性别是否公开（自己的设置页需要回显）。 */
    private Boolean genderPublic;
    /** 年龄是否公开。 */
    private Boolean agePublic;
    /**
     * 角色：0=普通用户 1=管理员。
     *
     * <p>前端只用它决定是否显示「管理后台」入口。
     * **权限校验在服务端**（`@PreAuthorize("hasRole('ADMIN')")`），
     * 前端篡改这个字段也调不动管理员接口。
     */
    private Integer role;
    private LocalDateTime createdAt;

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

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
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

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
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

    public Boolean getGenderPublic() {
        return genderPublic;
    }

    public void setGenderPublic(Boolean genderPublic) {
        this.genderPublic = genderPublic;
    }

    public Boolean getAgePublic() {
        return agePublic;
    }

    public void setAgePublic(Boolean agePublic) {
        this.agePublic = agePublic;
    }
}
