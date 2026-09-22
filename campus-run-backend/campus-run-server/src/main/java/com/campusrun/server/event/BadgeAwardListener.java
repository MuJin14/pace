package com.campusrun.server.event;

import com.campusrun.server.dto.response.BadgeResponse;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.entity.Badge;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Component
public class BadgeAwardListener {

    private final WebSocketSessionManager sessionManager;

    public BadgeAwardListener(WebSocketSessionManager sessionManager) {
        this.sessionManager = sessionManager;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onAwarded(BadgeAwardedEvent event) {
        Badge badge = event.getBadge();
        BadgeResponse response = new BadgeResponse();
        response.setId(badge.getId());
        response.setCode(badge.getCode());
        response.setName(badge.getName());
        response.setIcon(badge.getIcon());
        response.setDescription(badge.getDescription());
        response.setRuleType(badge.getRuleType());
        response.setRuleValue(badge.getRuleValue());
        response.setEarned(true);

        sessionManager.sendToUser(event.getUserId(), new WsMessage("badge_awarded", response));
    }
}
