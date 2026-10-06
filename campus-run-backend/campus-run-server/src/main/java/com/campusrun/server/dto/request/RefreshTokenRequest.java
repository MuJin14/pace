package com.campusrun.server.dto.request;

import jakarta.validation.constraints.NotBlank;

/**
 * 刷新令牌请求：用长效 refresh token 换一个新的 access token。
 *
 * <p>客户端在 access token 过期（或收到 401）时调用，避免让用户重新输密码。
 */
public class RefreshTokenRequest {

    @NotBlank(message = "刷新令牌不能为空")
    private String refreshToken;

    public String getRefreshToken() {
        return refreshToken;
    }

    public void setRefreshToken(String refreshToken) {
        this.refreshToken = refreshToken;
    }
}
