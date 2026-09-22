package com.campusrun.server.websocket;

import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.service.MessageService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ChatWebSocketHandlerTest {

    private final WebSocketSessionManager sessionManager = mock(WebSocketSessionManager.class);
    private final MessageService messageService = mock(MessageService.class);
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ChatWebSocketHandler handler =
            new ChatWebSocketHandler(sessionManager, messageService, objectMapper);

    private WebSocketSession session(Long userId) {
        WebSocketSession session = mock(WebSocketSession.class);
        Map<String, Object> attrs = new HashMap<>();
        attrs.put(AuthHandshakeInterceptor.ATTR_USER_ID, userId);
        when(session.getAttributes()).thenReturn(attrs);
        return session;
    }

    @Test
    void afterConnectionEstablished_registersAndPushesOffline() throws Exception {
        WebSocketSession session = session(1L);

        handler.afterConnectionEstablished(session);

        verify(sessionManager).addSession(1L, session);
        verify(messageService).pushOfflineMessages(1L);
    }

    @Test
    void handleTextMessage_message_callsSendAndAcks() throws Exception {
        WebSocketSession session = session(1L);
        ChatMessageResponse resp = new ChatMessageResponse();
        resp.setMessageId(10L);
        resp.setSenderId(1L);
        resp.setReceiverId(2L);
        resp.setContent("hi");
        resp.setTimestamp(123L);
        when(messageService.sendMessage(1L, 2L, "hi")).thenReturn(resp);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"message\",\"data\":{\"receiverId\":2,\"content\":\"hi\"}}"));

        verify(messageService).sendMessage(1L, 2L, "hi");
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertTrue(captor.getValue().getPayload().contains("\"type\":\"ack\""));
        assertTrue(captor.getValue().getPayload().contains("\"messageId\":10"));
    }

    @Test
    void handleTextMessage_heartbeat_repliesPong() throws Exception {
        WebSocketSession session = session(1L);

        handler.handleTextMessage(session, new TextMessage("{\"type\":\"heartbeat\"}"));

        verify(sessionManager).touch(1L);
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertTrue(captor.getValue().getPayload().contains("\"type\":\"pong\""));
    }

    @Test
    void handleTextMessage_invalidJson_sendsError() throws Exception {
        WebSocketSession session = session(1L);

        handler.handleTextMessage(session, new TextMessage("not json"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertTrue(captor.getValue().getPayload().contains("\"type\":\"error\""));
    }

    @Test
    void afterConnectionClosed_removesSession() {
        WebSocketSession session = session(1L);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        verify(sessionManager).removeSession(1L, session);
    }
}
