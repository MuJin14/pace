package com.campusrun.server.websocket;

import com.campusrun.server.dto.websocket.WsMessage;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WebSocketSessionManagerTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final WebSocketSessionManager manager = new WebSocketSessionManager(objectMapper);

    private WebSocketSession openSession() {
        WebSocketSession session = mock(WebSocketSession.class);
        when(session.isOpen()).thenReturn(true);
        return session;
    }

    @Test
    void addAndIsOnline() {
        WebSocketSession session = openSession();

        manager.addSession(1L, session);

        assertTrue(manager.isOnline(1L));
    }

    @Test
    void removeSession_makesOffline() {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);

        manager.removeSession(1L, session);

        assertFalse(manager.isOnline(1L));
    }

    @Test
    void sendToUser_whenOffline_returnsFalse() {
        assertFalse(manager.sendToUser(1L, new WsMessage("pong", null)));
    }

    @Test
    void sendToUser_whenOnline_sendsJsonAndReturnsTrue() throws Exception {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);

        boolean sent = manager.sendToUser(1L, new WsMessage("pong", null));

        assertTrue(sent);
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertTrue(captor.getValue().getPayload().contains("\"type\":\"pong\""));
    }

    @Test
    void sendToUser_closedSession_returnsFalse() {
        WebSocketSession session = mock(WebSocketSession.class);
        when(session.isOpen()).thenReturn(false);
        manager.addSession(1L, session);

        assertFalse(manager.sendToUser(1L, new WsMessage("pong", null)));
    }

    @Test
    void sweep_removesIdleSessionEvenIfCloseFails() throws Exception {
        WebSocketSession session = openSession();
        doThrow(new IOException("boom")).when(session).close(any(CloseStatus.class));
        manager.addSession(1L, session);

        Thread.sleep(30);
        manager.sweep(1);

        assertFalse(manager.isOnline(1L));
    }
}
