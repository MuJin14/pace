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

@Component
public class JwtTokenProvider {

    private final JwtProperties jwtProperties;
    private final SecretKey secretKey;

    public JwtTokenProvider(JwtProperties jwtProperties) {
        this.jwtProperties = jwtProperties;
        this.secretKey = Keys.hmacShaKeyFor(jwtProperties.getSecret().getBytes(StandardCharsets.UTF_8));
    }

    public String generateToken(Long userId, String uniqueId) {
        return generateToken(userId, uniqueId, UserRole.USER.getCode());
    }

    public String generateToken(Long userId, String uniqueId, Integer role) {
        Date now = new Date();
        Date expiry = new Date(now.getTime() + jwtProperties.getExpiration() * 1000L);
        int effectiveRole = role == null ? UserRole.USER.getCode() : role;
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim("uniqueId", uniqueId)
                .claim("role", effectiveRole)
                .issuedAt(now)
                .expiration(expiry)
                .signWith(secretKey)
                .compact();
    }

    public Claims parseToken(String token) {
        return Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public boolean validateToken(String token) {
        try {
            parseToken(token);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
