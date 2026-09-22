package com.campusrun.server.task;

import com.campusrun.server.websocket.WebSocketSessionManager;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class ChatSessionScheduler {

    private static final long IDLE_TIMEOUT_MILLIS = 90_000L;

    private final WebSocketSessionManager sessionManager;

    public ChatSessionScheduler(WebSocketSessionManager sessionManager) {
        this.sessionManager = sessionManager;
    }

    @Scheduled(fixedDelay = 60_000)
    public void sweepIdleSessions() {
        sessionManager.sweep(IDLE_TIMEOUT_MILLIS);
    }
}
