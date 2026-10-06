package com.campusrun.server.security;

import com.campusrun.server.config.JwtProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtTokenProviderTest {

    private static final String SECRET = "test-secret-key-for-jwt-that-is-long-enough-1234567890";

    private JwtTokenProvider newProvider(long expiration) {
        JwtProperties properties = new JwtProperties();
        properties.setSecret(SECRET);
        properties.setExpiration(expiration);
        properties.setRefreshExpiration(expiration * 10);
        return new JwtTokenProvider(properties);
    }

    @Test
    void generateAndParse_returnsCorrectClaims() {
        JwtTokenProvider provider = newProvider(3600L);
        String token = provider.generateToken(123L, "CR-00001234");
        Claims claims = provider.parseToken(token);
        assertEquals("123", claims.getSubject());
        assertEquals("CR-00001234", claims.get("uniqueId", String.class));
    }

    @Test
    void validateToken_expiredTokenReturnsFalse() {
        JwtTokenProvider provider = newProvider(-60L);
        String token = provider.generateToken(1L, "CR-00000001");
        assertFalse(provider.validateToken(token));
    }

    @Test
    @DisplayName("access 与 refresh 是两种不同令牌，且能各自解析")
    void accessAndRefreshAreDistinct() {
        JwtTokenProvider provider = newProvider(3600L);
        String access = provider.generateAccessToken(1L, "CR-00000001", 0);
        String refresh = provider.generateRefreshToken(1L, "CR-00000001", 0);

        assertNotEquals(access, refresh);
        assertEquals("access", provider.parseAccessToken(access).get("typ", String.class));
        assertEquals("refresh", provider.parseRefreshToken(refresh).get("typ", String.class));
    }

    @Test
    @DisplayName("refresh token 不能当 access token 用（防长效令牌越权）")
    void refreshTokenRejectedAsAccessToken() {
        JwtTokenProvider provider = newProvider(3600L);
        String refresh = provider.generateRefreshToken(1L, "CR-00000001", 0);

        assertThrows(JwtException.class, () -> provider.parseAccessToken(refresh));
    }

    @Test
    @DisplayName("access token 不能当 refresh token 用")
    void accessTokenRejectedAsRefreshToken() {
        JwtTokenProvider provider = newProvider(3600L);
        String access = provider.generateAccessToken(1L, "CR-00000001", 0);

        assertThrows(JwtException.class, () -> provider.parseRefreshToken(access));
    }

    @Test
    @DisplayName("refresh token 有效期长于 access token")
    void refreshLivesLongerThanAccess() {
        JwtTokenProvider provider = newProvider(3600L);
        String refresh = provider.generateRefreshToken(1L, "CR-00000001", 0);
        // access 有效期 1 小时，refresh 是它的 10 倍；两者都不应过期
        assertTrue(provider.validateToken(refresh));
        assertEquals(36000L, provider.getRefreshExpirationSeconds());
    }
}
