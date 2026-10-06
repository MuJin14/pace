package com.campusrun.server.security;

/**
 * JWT 用途区分。
 *
 * <p>背景：原先只签发一种「万能 token」，有效期 24 小时。这带来两个问题：
 * 用户在 24 小时后被强制登出；且没有任何续期手段，只能重新输密码。
 * 拆成 access + refresh 两种用途后，可以做到「access 短命、refresh 长命」：
 * access 泄露的窗口从 24 小时缩短到 {@code jwt.access-expiration}，
 * 而用户正常使用期间由前端静默续期，不再需要重新登录。
 *
 * <p>关键安全点：refresh token **不能**当 access token 用。两类 token 都带
 * {@code typ} 声明，{@link JwtTokenProvider#parseAccessToken} 会校验它，
 * 避免有人拿长效的 refresh token 直接访问业务接口。
 */
public enum TokenType {

    /** 访问令牌：随每个业务请求发送，有效期短。 */
    ACCESS("access"),

    /** 刷新令牌：只用于换新 access token，有效期长。 */
    REFRESH("refresh");

    private final String claimValue;

    TokenType(String claimValue) {
        this.claimValue = claimValue;
    }

    public String claimValue() {
        return claimValue;
    }
}
