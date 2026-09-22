package com.campusrun.server.security;

import com.campusrun.server.config.JwtProperties;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class JwtTokenProviderTest {

    private static final String SECRET = "test-secret-key-for-jwt-that-is-long-enough-1234567890";

    private JwtTokenProvider newProvider(long expiration) {
        JwtProperties properties = new JwtProperties();
        properties.setSecret(SECRET);
        properties.setExpiration(expiration);
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
}
