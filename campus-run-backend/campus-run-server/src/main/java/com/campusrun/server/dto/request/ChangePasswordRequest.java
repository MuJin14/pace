package com.campusrun.server.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 修改密码。
 *
 * <p>必须校验旧密码：只凭 access token 就能改密的话，token 一旦泄露
 * （例如被日志、代理记录）攻击者可以直接改掉密码把账号锁死。
 *
 * <p>长度下限 8 位与注册保持一致 —— 两侧规则不同会让用户觉得「注册能用的密码改不了」。
 */
public class ChangePasswordRequest {

    @NotBlank(message = "请输入当前密码")
    private String oldPassword;

    @NotBlank(message = "请输入新密码")
    @Size(min = 8, max = 64, message = "新密码长度需在 8-64 之间")
    private String newPassword;

    public String getOldPassword() {
        return oldPassword;
    }

    public void setOldPassword(String oldPassword) {
        this.oldPassword = oldPassword;
    }

    public String getNewPassword() {
        return newPassword;
    }

    public void setNewPassword(String newPassword) {
        this.newPassword = newPassword;
    }
}
