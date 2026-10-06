package com.campusrun.server.security;

import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.enums.UserRole;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * JWT 签发与校验。
 *
 * <p>两类令牌（见 {@link TokenType}）：
 * <ul>
 *   <li>access：有效期 {@code jwt.expiration}（默认 2 小时），用于业务接口；</li>
 *   <li>refresh：有效期 {@code jwt.refresh-expiration}（默认 30 天），仅用于换新 access。</li>
 * </ul>
 * 两者都带 {@code typ} 声明，且 {@link #parseAccessToken(String)} 只接受 access，
 * 因此长效的 refresh token 无法被拿来直接调业务接口。
 */
@Component
public class JwtTokenProvider {

    private static final String CLAIM_TYPE = "typ";
    private static final String CLAIM_UNIQUE_ID = "uniqueId";
    private static final String CLAIM_ROLE = "role";
    /** 令牌版本，与 user.token_version 比对；不相等即视为已失效。 */
    private static final String CLAIM_TOKEN_VERSION = "ver";

    private final JwtProperties jwtProperties;
    private final SecretKey secretKey;

    public JwtTokenProvider(JwtProperties jwtProperties) {
        this.jwtProperties = jwtProperties;
        this.secretKey = Keys.hmacShaKeyFor(jwtProperties.getSecret().getBytes(StandardCharsets.UTF_8));
    }

    /** 兼容既有调用：签发 access token。 */
    public String generateToken(Long userId, String uniqueId) {
        return generateToken(userId, uniqueId, UserRole.USER.getCode());
    }

    /** 兼容既有调用：签发 access token（版本按 0）。 */
    public String generateToken(Long userId, String uniqueId, Integer role) {
        return generateAccessToken(userId, uniqueId, role, 0);
    }

    public String generateAccessToken(Long userId, String uniqueId, Integer role) {
        return generateAccessToken(userId, uniqueId, role, 0);
    }

    public String generateRefreshToken(Long userId, String uniqueId, Integer role) {
        return generateRefreshToken(userId, uniqueId, role, 0);
    }

    public String generateAccessToken(Long userId, String uniqueId, Integer role, int tokenVersion) {
        return generate(userId, uniqueId, role, tokenVersion, TokenType.ACCESS,
                jwtProperties.getExpiration());
    }

    public String generateRefreshToken(Long userId, String uniqueId, Integer role, int tokenVersion) {
        return generate(userId, uniqueId, role, tokenVersion, TokenType.REFRESH,
                jwtProperties.getRefreshExpiration());
    }

    /**
     * 读令牌里的版本号；老令牌没有这个 claim 时返回 0。
     *
     * <p>返回 0 而不是抛异常，是为了让这次升级**不把已有用户踢下线** ——
     * 迁移时所有用户的 token_version 都是 0，老令牌与之相等，继续可用。
     */
    public int tokenVersionOf(Claims claims) {
        Integer v = claims.get(CLAIM_TOKEN_VERSION, Integer.class);
        return v == null ? 0 : v;
    }

    private String generate(Long userId, String uniqueId, Integer role, int tokenVersion,
                            TokenType type, long ttlSeconds) {
        Date now = new Date();
        Date expiry = new Date(now.getTime() + ttlSeconds * 1000L);
        int effectiveRole = role == null ? UserRole.USER.getCode() : role;
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim(CLAIM_UNIQUE_ID, uniqueId)
                .claim(CLAIM_ROLE, effectiveRole)
                .claim(CLAIM_TOKEN_VERSION, tokenVersion)
                .claim(CLAIM_TYPE, type.claimValue())
                .issuedAt(now)
                .expiration(expiry)
                .signWith(secretKey)
                .compact();
    }

    /**
     * 解析 access token。refresh token（或缺少 typ 的历史 token）会被拒绝。
     *
     * @throws io.jsonwebtoken.JwtException 签名无效、过期或类型不符
     */
    public Claims parseAccessToken(String token) {
        Claims claims = parseToken(token);
        requireType(claims, TokenType.ACCESS);
        return claims;
    }

    /** 解析 refresh token；access token 会被拒绝。 */
    public Claims parseRefreshToken(String token) {
        Claims claims = parseToken(token);
        requireType(claims, TokenType.REFRESH);
        return claims;
    }

    private void requireType(Claims claims, TokenType expected) {
        Object raw = claims.get(CLAIM_TYPE);
        if (raw == null || !expected.claimValue().equals(String.valueOf(raw))) {
            throw new io.jsonwebtoken.JwtException("令牌用途不符，期望 " + expected.claimValue());
        }
    }

    /** 不校验用途的低层解析（仅用于诊断/测试）。 */
    public Claims parseToken(String token) {
        return Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    /** 兼容既有调用：校验签名与有效期（不区分用途）。 */
    public boolean validateToken(String token) {
        try {
            parseToken(token);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public long getAccessExpirationSeconds() {
        return jwtProperties.getExpiration();
    }

    public long getRefreshExpirationSeconds() {
        return jwtProperties.getRefreshExpiration();
    }
}
