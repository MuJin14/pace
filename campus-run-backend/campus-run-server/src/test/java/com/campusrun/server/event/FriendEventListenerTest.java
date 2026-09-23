package com.campusrun.server.event;

import com.campusrun.server.dto.websocket.FriendAcceptedPushData;
import com.campusrun.server.dto.websocket.FriendDeletedPushData;
import com.campusrun.server.dto.websocket.FriendRequestPushData;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class FriendEventListenerTest {

    @Mock
    private WebSocketSessionManager sessionManager;

    @Test
    void onFriendRequest_sendsFriendRequestMessage() {
        FriendEventListener listener = new FriendEventListener(sessionManager);
        FriendRequestPushData data = new FriendRequestPushData();
        data.setRequestId(1L);
        data.setFromUserId(2L);
        data.setFromUniqueId("CR-00000002");
        data.setFromNickname("甲");
        data.setFromAvatarUrl(null);
        data.setCreatedAt(LocalDateTime.of(2026, 9, 22, 20, 0));

        listener.onFriendRequest(new FriendRequestEvent(3L, data));

        ArgumentCaptor<WsMessage> captor = ArgumentCaptor.forClass(WsMessage.class);
        verify(sessionManager).sendToUser(eq(3L), captor.capture());
        WsMessage message = captor.getValue();
        assertEquals("friend_request", message.getType());
        assertEquals(data, message.getData());
    }

    @Test
    void onFriendAccepted_sendsFriendAcceptedMessage() {
        FriendEventListener listener = new FriendEventListener(sessionManager);
        FriendAcceptedPushData data = new FriendAcceptedPushData();
        data.setFriendUserId(2L);
        data.setFriendUniqueId("CR-00000002");
        data.setFriendNickname("乙");
        data.setFriendAvatarUrl(null);

        listener.onFriendAccepted(new FriendAcceptedEvent(3L, data));

        ArgumentCaptor<WsMessage> captor = ArgumentCaptor.forClass(WsMessage.class);
        verify(sessionManager).sendToUser(eq(3L), captor.capture());
        WsMessage message = captor.getValue();
        assertEquals("friend_accepted", message.getType());
        assertEquals(data, message.getData());
    }

    @Test
    void onFriendDeleted_sendsFriendDeletedMessage() {
        FriendEventListener listener = new FriendEventListener(sessionManager);
        FriendDeletedPushData data = new FriendDeletedPushData();
        data.setFriendUserId(2L);

        listener.onFriendDeleted(new FriendDeletedEvent(3L, data));

        ArgumentCaptor<WsMessage> captor = ArgumentCaptor.forClass(WsMessage.class);
        verify(sessionManager).sendToUser(eq(3L), captor.capture());
        WsMessage message = captor.getValue();
        assertEquals("friend_deleted", message.getType());
        assertEquals(data, message.getData());
    }
}
