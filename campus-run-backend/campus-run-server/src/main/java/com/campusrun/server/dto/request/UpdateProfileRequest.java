package com.campusrun.server.dto.request;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;

/**
 * 更新个人资料。
 *
 * <p>只允许改昵称、头像、性别、年龄及其可见性：手机号是账号标识（改它要走换绑流程）；
 * 专属 ID 是别人加你的凭据（改它会让好友找不到你），两者都不在这里。
 *
 * <p><b>字段为 null = 不修改该字段</b>（PATCH 语义），避免客户端漏传就把资料清空。
 *
 * <p>可见性字段用 {@code Boolean} 而非 {@code boolean}，同样是为了 PATCH 语义：
 * 原始类型无法区分「没传」与「传了 false」。
 */
public class UpdateProfileRequest {

    @Size(min = 1, max = 20, message = "昵称长度需在 1-20 之间")
    private String nickname;

    @Size(max = 255, message = "头像地址过长")
    private String avatarUrl;

    /** 性别：0=保密 1=男 2=女。null = 不修改。 */
    @Min(value = 0, message = "性别取值非法")
    @Max(value = 2, message = "性别取值非法")
    private Integer gender;

    /** 年龄 1-120。null = 不修改。 */
    @Min(value = 1, message = "年龄需在 1-120 之间")
    @Max(value = 120, message = "年龄需在 1-120 之间")
    private Integer age;

    /** 性别是否对他人公开。null = 不修改。 */
    private Boolean genderPublic;

    /** 年龄是否对他人公开。null = 不修改。 */
    private Boolean agePublic;

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
