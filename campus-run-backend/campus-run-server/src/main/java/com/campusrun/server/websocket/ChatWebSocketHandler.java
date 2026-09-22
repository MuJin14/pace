package com.campusrun.server.websocket;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.service.MessageService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.util.Map;

@Component
public class ChatWebSocketHandler extends TextWebSocketHandler {

    private final WebSocketSessionManager sessionManager;
    private final MessageService messageService;
    private final ObjectMapper objectMapper;

    public ChatWebSocketHandler(WebSocketSessionManager sessionManager,
                                MessageService messageService,
                                ObjectMapper objectMapper) {
        this.sessionManager = sessionManager;
        this.messageService = messageService;
        this.objectMapper = objectMapper;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        Long userId = currentUserId(session);
        if (userId == null) {
            session.close(CloseStatus.NOT_ACCEPTABLE);
            return;
        }
        sessionManager.addSession(userId, session);
        messageService.pushOfflineMessages(userId);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        Long userId = currentUserId(session);
        if (userId == null) {
            session.close(CloseStatus.NOT_ACCEPTABLE);
            return;
        }
        try {
            JsonNode root = objectMapper.readTree(message.getPayload());
            String type = root.path("type").asText();
            switch (type) {
                case "message" -> {
                    JsonNode data = root.path("data");
                    Long receiverId = data.hasNonNull("receiverId") ? data.get("receiverId").asLong() : null;
                    String content = data.path("content").asText(null);
                    ChatMessageResponse resp = messageService.sendMessage(userId, receiverId, content);
                    send(session, new WsMessage("ack", resp));
                }
                case "heartbeat" -> {
                    sessionManager.touch(userId);
                    send(session, new WsMessage("pong", null));
                }
                default -> send(session, error(ErrorCode.PARAM_ERROR.getCode(), "未知消息类型"));
            }
        } catch (BusinessException e) {
            send(session, error(e.getCode(), e.getMessage()));
        } catch (Exception e) {
            send(session, error(ErrorCode.PARAM_ERROR.getCode(), "消息格式错误"));
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        Long userId = currentUserId(session);
        if (userId != null) {
            sessionManager.removeSession(userId, session);
        }
    }

    private Long currentUserId(WebSocketSession session) {
        Object value = session.getAttributes().get(AuthHandshakeInterceptor.ATTR_USER_ID);
        return value instanceof Long l ? l : null;
    }

    private void send(WebSocketSession session, Object payload) {
        try {
            String json = objectMapper.writeValueAsString(payload);
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
        } catch (Exception ignored) {
            // 发送失败忽略，消息已落库，走离线补投
        }
    }

    private WsMessage error(int code, String message) {
        return new WsMessage("error", Map.of("code", code, "message", message));
    }
}
