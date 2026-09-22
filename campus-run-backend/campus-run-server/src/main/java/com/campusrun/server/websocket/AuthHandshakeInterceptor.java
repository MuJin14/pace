package com.campusrun.server.websocket;

import com.campusrun.server.security.JwtTokenProvider;
import io.jsonwebtoken.Claims;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.List;
import java.util.Map;

@Component
public class AuthHandshakeInterceptor implements HandshakeInterceptor {

    public static final String ATTR_USER_ID = "userId";

    private final JwtTokenProvider jwtTokenProvider;

    public AuthHandshakeInterceptor(JwtTokenProvider jwtTokenProvider) {
        this.jwtTokenProvider = jwtTokenProvider;
    }

    @Override
    public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                   WebSocketHandler wsHandler, Map<String, Object> attributes) {
        String token = extractToken(request);
        if (!StringUtils.hasText(token) || !jwtTokenProvider.validateToken(token)) {
            return false;
        }
        Claims claims = jwtTokenProvider.parseToken(token);
        attributes.put(ATTR_USER_ID, Long.valueOf(claims.getSubject()));
        return true;
    }

    @Override
    public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response,
                               WebSocketHandler wsHandler, Exception exception) {
        // no-op
    }

    private String extractToken(ServerHttpRequest request) {
        String token = UriComponentsBuilder.fromUri(request.getURI())
                .build().getQueryParams().getFirst("token");
        if (token == null) {
            List<String> auth = request.getHeaders().get("Authorization");
            if (auth != null && !auth.isEmpty() && auth.get(0).startsWith("Bearer ")) {
                token = auth.get(0).substring(7);
            }
        }
        return token;
    }
}
