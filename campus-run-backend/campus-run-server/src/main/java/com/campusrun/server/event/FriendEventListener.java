package com.campusrun.server.event;

import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 好友事件在事务提交后通过 WebSocket 推送给对端。
 * 推送失败仅记录日志，不影响主事务；对方不在线时由 {@link WebSocketSessionManager#sendToUser} 静默丢弃。
 */
@Component
public class FriendEventListener {

    private static final Logger log = LoggerFactory.getLogger(FriendEventListener.class);

    private final WebSocketSessionManager sessionManager;

    public FriendEventListener(WebSocketSessionManager sessionManager) {
        this.sessionManager = sessionManager;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onFriendRequest(FriendRequestEvent event) {
        try {
            sessionManager.sendToUser(event.getTargetUserId(), new WsMessage("friend_request", event.getData()));
        } catch (Exception ex) {
            log.warn("好友申请推送失败 targetUserId={}", event.getTargetUserId(), ex);
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onFriendAccepted(FriendAcceptedEvent event) {
        try {
            sessionManager.sendToUser(event.getTargetUserId(), new WsMessage("friend_accepted", event.getData()));
        } catch (Exception ex) {
            log.warn("好友接受推送失败 targetUserId={}", event.getTargetUserId(), ex);
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onFriendDeleted(FriendDeletedEvent event) {
        try {
            sessionManager.sendToUser(event.getTargetUserId(), new WsMessage("friend_deleted", event.getData()));
        } catch (Exception ex) {
            log.warn("好友删除推送失败 targetUserId={}", event.getTargetUserId(), ex);
        }
    }
}
