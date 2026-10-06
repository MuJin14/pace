package com.campusrun.server.dto.response;

public class LoginResponse {

    /** 访问令牌（access），有效期短；用于日常业务请求。 */
    private String token;

    /** 刷新令牌（refresh），有效期长；仅用于 POST /api/v1/auth/refresh 换新 access token。 */
    private String refreshToken;

    private Long userId;
    private String uniqueId;
    private String nickname;
    private String phone;
    private String avatarUrl;

    /**
     * 用户角色：0 = 普通用户，1 = 管理员。
     *
     * <p>为什么必须出现在登录响应里：App 用 {@code role} 决定是否显示
     * 「管理后台」入口（{@code User.isAdmin => role == 1}），而它的解析是
     * {@code json['role'] ?? 0}。登录响应缺这个字段时，管理员登录后会被当成
     * 普通用户，入口只有等 {@code /user/me} 返回后才出现 ——
     * 刷新或重启的窗口期里入口是消失的，看起来就像「升级后管理员权限没了」。
     *
     * <p>这不构成越权：真正的权限校验在后端 {@code ROLE_ADMIN} 上，
     * 前端隐藏入口只是 UI 便利。
     */
    private Integer role;

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }

    public String getRefreshToken() {
        return refreshToken;
    }

    public void setRefreshToken(String refreshToken) {
        this.refreshToken = refreshToken;
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
}
