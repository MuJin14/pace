package com.campusrun.server.websocket;

import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.security.JwtTokenProvider;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.web.socket.WebSocketHandler;

import java.net.URI;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AuthHandshakeInterceptorTest {

    private JwtTokenProvider jwtTokenProvider;
    private AuthHandshakeInterceptor interceptor;

    @BeforeEach
    void setUp() {
        JwtProperties props = new JwtProperties();
        props.setSecret("test-secret-key-for-jwt-that-is-long-enough-1234567890");
        props.setExpiration(3600L);
        jwtTokenProvider = new JwtTokenProvider(props);
        interceptor = new AuthHandshakeInterceptor(jwtTokenProvider);
    }

    private ServerHttpRequest request(String uri) {
        ServerHttpRequest request = mock(ServerHttpRequest.class);
        when(request.getURI()).thenReturn(URI.create(uri));
        when(request.getHeaders()).thenReturn(new HttpHeaders());
        return request;
    }

    @Test
    void validToken_returnsTrue_andPutsUserId() {
        String token = jwtTokenProvider.generateToken(1L, "CR-00001234");
        Map<String, Object> attrs = new HashMap<>();

        boolean ok = interceptor.beforeHandshake(
                request("ws://localhost/ws?token=" + token),
                mock(ServerHttpResponse.class), mock(WebSocketHandler.class), attrs);

        assertTrue(ok);
        assertEquals(1L, (Long) attrs.get(AuthHandshakeInterceptor.ATTR_USER_ID));
    }

    @Test
    void missingToken_returnsFalse() {
        Map<String, Object> attrs = new HashMap<>();

        boolean ok = interceptor.beforeHandshake(
                request("ws://localhost/ws"),
                mock(ServerHttpResponse.class), mock(WebSocketHandler.class), attrs);

        assertFalse(ok);
    }

    @Test
    void invalidToken_returnsFalse() {
        Map<String, Object> attrs = new HashMap<>();

        boolean ok = interceptor.beforeHandshake(
                request("ws://localhost/ws?token=invalid"),
                mock(ServerHttpResponse.class), mock(WebSocketHandler.class), attrs);

        assertFalse(ok);
    }
}
