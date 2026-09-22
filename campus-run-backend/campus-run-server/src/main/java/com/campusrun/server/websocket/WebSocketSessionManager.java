package com.campusrun.server.websocket;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.concurrent.ConcurrentHashMap;

@Component
public class WebSocketSessionManager {

    private final ConcurrentHashMap<Long, WebSocketSession> sessions = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Long, Long> lastActiveAt = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper;

    public WebSocketSessionManager(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public void addSession(Long userId, WebSocketSession session) {
        sessions.put(userId, session);
        lastActiveAt.put(userId, System.currentTimeMillis());
    }

    public void removeSession(Long userId, WebSocketSession session) {
        sessions.remove(userId, session);
        lastActiveAt.remove(userId);
    }

    public boolean isOnline(Long userId) {
        return sessions.containsKey(userId);
    }

    public boolean sendToUser(Long userId, Object payload) {
        WebSocketSession session = sessions.get(userId);
        if (session == null || !session.isOpen()) {
            return false;
        }
        try {
            String json = objectMapper.writeValueAsString(payload);
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public void touch(Long userId) {
        lastActiveAt.put(userId, System.currentTimeMillis());
    }

    public void sweep(long idleTimeoutMillis) {
        long now = System.currentTimeMillis();
        sessions.forEach((userId, session) -> {
            Long last = lastActiveAt.get(userId);
            if (last != null && now - last > idleTimeoutMillis) {
                try {
                    session.close(CloseStatus.SESSION_NOT_RELIABLE);
                } catch (Exception ignored) {
                    // 关闭失败也强制清理，不依赖 close 回调
                }
                sessions.remove(userId, session);
                lastActiveAt.remove(userId);
            }
        });
    }
}
