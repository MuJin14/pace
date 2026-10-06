package com.campusrun.server.dto.response;

/**
 * 管理员重置用户密码后的结果。
 *
 * <p>{@code temporaryPassword} 是**唯一一次**能拿到明文的地方：
 * 服务端只存 BCrypt 哈希，重置后无法再次读回。
 * 管理员必须当场把它告知用户（App 里会显示并可复制）。
 */
public class PasswordResetResult {

    private Long userId;
    private String nickname;
    private String temporaryPassword;

    public PasswordResetResult() {
    }

    public PasswordResetResult(Long userId, String nickname, String temporaryPassword) {
        this.userId = userId;
        this.nickname = nickname;
        this.temporaryPassword = temporaryPassword;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public String getTemporaryPassword() {
        return temporaryPassword;
    }

    public void setTemporaryPassword(String temporaryPassword) {
        this.temporaryPassword = temporaryPassword;
    }
}
