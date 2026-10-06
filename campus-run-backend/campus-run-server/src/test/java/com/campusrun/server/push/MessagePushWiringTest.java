package com.campusrun.server.push;

import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.entity.Message;
import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.mapper.MessageMapper;
import com.campusrun.server.service.impl.MessageServiceImpl;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 发消息 → 离线推送 的接线是否正确。
 *
 * <p>最容易搞错的判断是「什么时候该推」：
 * <ul>
 *   <li>对方**在线**时不能推 —— App 已经用 WebSocket 显示了，再弹系统通知是重复打扰；</li>
 *   <li>对方**离线**时必须推 —— 这正是离线推送存在的唯一理由。</li>
 * </ul>
 * 另外消息必须**先落库再推**（推送失败不能丢消息）。
 */
@ExtendWith(MockitoExtension.class)
class MessagePushWiringTest {

    @Mock
    private MessageMapper messageMapper;
    @Mock
    private FriendshipMapper friendshipMapper;
    @Mock
    private WebSocketSessionManager sessionManager;
    @Mock
    private PushService pushService;

    private MessageServiceImpl messageService;

    @BeforeEach
    void setUp() {
        messageService = new MessageServiceImpl(messageMapper, friendshipMapper, sessionManager, pushService);
    }

    /** 造出「sender 与 receiver 是好友」的前提。 */
    private void friends() {
        when(friendshipMapper.selectCount(any())).thenReturn(1L);
    }

    @Test
    @DisplayName("对方离线 → 发完消息后触发推送，标题用发件人昵称")
    void offlineReceiver_getsPush() {
        friends();
        when(sessionManager.isOnline(2L)).thenReturn(false);
        when(pushService.nicknameOf(1L)).thenReturn("Mujin");
        // insert 时回填自增 id（MyBatis-Plus 会写回 message.id）
        when(messageMapper.insert(any(Message.class))).thenAnswer(inv -> {
            Message m = inv.getArgument(0);
            m.setId(42L);
            return 1;
        });

        ChatMessageResponse resp = messageService.sendMessage(1L, 2L, "在吗");

        assertEquals(42L, resp.getMessageId());
        verify(pushService).pushMessage(eq(2L), eq("Mujin"), eq("在吗"), eq(42L));
    }

    @Test
    @DisplayName("对方在线 → 不推送（避免与 WebSocket 收到的消息重复打扰）")
    void onlineReceiver_noPush() {
        friends();
        when(sessionManager.isOnline(2L)).thenReturn(true);
        when(sessionManager.sendToUser(eq(2L), any())).thenReturn(true);
        when(messageMapper.insert(any(Message.class))).thenReturn(1);

        messageService.sendMessage(1L, 2L, "在吗");

        verify(pushService, never()).pushMessage(anyLong(), any(), anyString(), anyLong());
    }

    @Test
    @DisplayName("消息先落库，再推送（推送失败不能丢消息）")
    void messageIsPersistedBeforePush() {
        friends();
        when(sessionManager.isOnline(2L)).thenReturn(false);
        when(pushService.nicknameOf(1L)).thenReturn("Mujin");
        when(messageMapper.insert(any(Message.class))).thenAnswer(inv -> {
            Message m = inv.getArgument(0);
            m.setId(7L);
            return 1;
        });

        messageService.sendMessage(1L, 2L, "先落库");

        var inOrder = org.mockito.Mockito.inOrder(messageMapper, pushService);
        inOrder.verify(messageMapper).insert(any(Message.class));
        inOrder.verify(pushService).pushMessage(anyLong(), any(), anyString(), anyLong());

        ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageMapper).insert(saved.capture());
        assertEquals(1L, saved.getValue().getSenderId());
        assertEquals(2L, saved.getValue().getReceiverId());
        assertEquals("先落库", saved.getValue().getContent());
    }

    @Test
    @DisplayName("不是好友 → 抛异常，且**不**推送（防止给陌生人推通知）")
    void nonFriend_doesNotPush() {
        when(friendshipMapper.selectCount(any())).thenReturn(0L);

        org.junit.jupiter.api.Assertions.assertThrows(
                com.campusrun.common.exception.BusinessException.class,
                () -> messageService.sendMessage(1L, 2L, "你好"));

        verify(pushService, never()).pushMessage(anyLong(), any(), anyString(), anyLong());
        verify(messageMapper, never()).insert(any(Message.class));
    }

    @Test
    @DisplayName("content 为空 → 不落库不推送")
    void blankContent_rejected() {
        org.junit.jupiter.api.Assertions.assertThrows(
                com.campusrun.common.exception.BusinessException.class,
                () -> messageService.sendMessage(1L, 2L, "   "));

        verify(messageMapper, never()).insert(any(Message.class));
        verify(pushService, never()).pushMessage(anyLong(), any(), anyString(), anyLong());
    }

    @Test
    @DisplayName("兼容构造器（无 pushService）时发消息仍正常，不 NPE")
    void withoutPushService_stillWorks() {
        MessageServiceImpl legacy = new MessageServiceImpl(messageMapper, friendshipMapper, sessionManager);
        friends();
        when(sessionManager.isOnline(2L)).thenReturn(false);
        when(messageMapper.insert(any(Message.class))).thenReturn(1);

        ChatMessageResponse resp = legacy.sendMessage(1L, 2L, "hi");

        assertEquals(1, resp.getType());
        verify(pushService, never()).pushMessage(anyLong(), any(), anyString(), anyLong());
    }
}
