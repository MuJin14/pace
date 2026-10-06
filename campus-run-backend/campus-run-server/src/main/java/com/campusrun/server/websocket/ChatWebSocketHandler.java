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
                    // type / mediaUrl 用于图片与表情包；不传时按文本处理，兼容旧客户端。
                    Integer msgType = data.hasNonNull("type") ? data.get("type").asInt() : null;
                    String mediaUrl = data.path("mediaUrl").asText(null);
                    // 客户端可选携带 clientMsgId：原样回显在 ack / error 里，
                    // 让客户端把响应与「哪一次发送」精确配对，而不是按 FIFO 猜。
                    String clientMsgId = data.path("clientMsgId").asText(null);
                    ChatMessageResponse resp =
                            messageService.sendMessage(userId, receiverId, content, msgType, mediaUrl);
                    send(session, new WsMessage("ack", withClientMsgId(resp, clientMsgId)));
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

    /**
     * 把 clientMsgId 附加到 ack 的响应体上。
     *
     * <p>用 Map 承载而不是给 {@code ChatMessageResponse} 加字段：clientMsgId 是
     * **传输层的关联标识**，不属于消息的业务模型，放进 DTO 会污染领域对象。
     */
    @SuppressWarnings("unchecked")
    private Object withClientMsgId(ChatMessageResponse resp, String clientMsgId) {
        if (clientMsgId == null || clientMsgId.isBlank()) {
            return resp;
        }
        Map<String, Object> payload = objectMapper.convertValue(resp, Map.class);
        payload.put("clientMsgId", clientMsgId);
        return payload;
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

    private WsMessage error(int code, String message, String clientMsgId) {
        Map<String, Object> data = new java.util.HashMap<>();
        data.put("code", code);
        data.put("message", message);
        if (clientMsgId != null && !clientMsgId.isBlank()) {
            data.put("clientMsgId", clientMsgId);
        }
        return new WsMessage("error", data);
    }
}
