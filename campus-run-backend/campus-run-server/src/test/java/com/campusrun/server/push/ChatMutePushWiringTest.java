package com.campusrun.server.push;

import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.mapper.MessageMapper;
import com.campusrun.server.service.ChatPreferenceService;
import com.campusrun.server.service.impl.MessageServiceImpl;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 免打扰与离线推送的接线。
 *
 * <p>要固化的语义边界：
 * <ul>
 *   <li><b>免打扰只拦通知，不拦消息</b>：消息照样落库、照样在线送达。
 *       用户说的是「别弹通知」，不是「别给我发消息」。</li>
 *   <li><b>方向是「接收方静音发送方」</b>：判断的是 receiver 对 sender 的设置，
 *       反过来查会变成「我一静音别人，别人就收不到我的消息」——完全错误的语义。</li>
 *   <li><b>对方在线时本来就不推</b>：免打扰的判断不应改变这一点。</li>
 * </ul>
 */
@ExtendWith(MockitoExtension.class)
class ChatMutePushWiringTest {

    private static final long SENDER = 1L;
    private static final long RECEIVER = 2L;

    @Mock
    private MessageMapper messageMapper;
    @Mock
    private FriendshipMapper friendshipMapper;
    @Mock
    private WebSocketSessionManager sessionManager;
    @Mock
    private PushService pushService;
    @Mock
    private ChatPreferenceService chatPreferenceService;

    private MessageServiceImpl messageService;

    @BeforeEach
    void setUp() {
        messageService = new MessageServiceImpl(messageMapper, friendshipMapper,
                sessionManager, pushService, chatPreferenceService);
    }

    private void friends() {
        when(friendshipMapper.selectCount(any())).thenReturn(1L);
    }

    @Test
    @DisplayName("对方离线且未免打扰 → 正常推送")
    void offlineAndNotMuted_pushes() {
        friends();
        when(sessionManager.isOnline(RECEIVER)).thenReturn(false);
        when(pushService.nicknameOf(SENDER)).thenReturn("甲");
        when(chatPreferenceService.isMuted(RECEIVER, SENDER)).thenReturn(false);

        messageService.sendMessage(SENDER, RECEIVER, "在吗", 1, null);

        verify(pushService).pushMessage(eq(RECEIVER), eq("甲"), eq("在吗"), nullable(Long.class));
    }

    @Test
    @DisplayName("对方离线但已免打扰 → 不推送（消息仍已落库）")
    void offlineAndMuted_doesNotPush() {
        friends();
        when(sessionManager.isOnline(RECEIVER)).thenReturn(false);
        when(chatPreferenceService.isMuted(RECEIVER, SENDER)).thenReturn(true);

        messageService.sendMessage(SENDER, RECEIVER, "在吗", 1, null);

        verify(pushService, never())
                .pushMessage(anyLong(), anyString(), anyString(), nullable(Long.class));
        // 关键：免打扰不等于不落库
        verify(messageMapper).insert(any(com.campusrun.server.entity.Message.class));
    }

    @Test
    @DisplayName("免打扰判断的方向必须是「接收方静音发送方」")
    void muteDirection_isReceiverSideCheck() {
        friends();
        when(sessionManager.isOnline(RECEIVER)).thenReturn(false);
        when(chatPreferenceService.isMuted(RECEIVER, SENDER)).thenReturn(true);

        messageService.sendMessage(SENDER, RECEIVER, "hi", 1, null);

        // 只应查 (receiver, sender)，不能反过来
        verify(chatPreferenceService).isMuted(RECEIVER, SENDER);
        verify(chatPreferenceService, never()).isMuted(SENDER, RECEIVER);
    }

    @Test
    @DisplayName("图片消息的推送正文用 [图片]，不能让通知栏空白")
    void imageMessage_pushPreviewIsPlaceholder() {
        friends();
        when(sessionManager.isOnline(RECEIVER)).thenReturn(false);
        when(pushService.nicknameOf(SENDER)).thenReturn("甲");
        when(chatPreferenceService.isMuted(RECEIVER, SENDER)).thenReturn(false);

        messageService.sendMessage(SENDER, RECEIVER, null, 2, "http://host/uploads/chat/a.jpg");

        verify(pushService).pushMessage(eq(RECEIVER), eq("甲"), eq("[图片]"), nullable(Long.class));
    }

    @Test
    @DisplayName("表情包消息的推送正文用 [表情]")
    void stickerMessage_pushPreviewIsPlaceholder() {
        friends();
        when(sessionManager.isOnline(RECEIVER)).thenReturn(false);
        when(pushService.nicknameOf(SENDER)).thenReturn("甲");
        when(chatPreferenceService.isMuted(RECEIVER, SENDER)).thenReturn(false);

        messageService.sendMessage(SENDER, RECEIVER, null, 3, "http://host/stickers/hi.png");

        verify(pushService).pushMessage(eq(RECEIVER), eq("甲"), eq("[表情]"), nullable(Long.class));
    }

    @Test
    @DisplayName("对方在线时本来就不推，且不应受免打扰影响")
    void onlineReceiver_doesNotPushRegardlessOfMute() {
        friends();
        when(sessionManager.isOnline(RECEIVER)).thenReturn(true);
        when(sessionManager.sendToUser(eq(RECEIVER), any())).thenReturn(true);

        messageService.sendMessage(SENDER, RECEIVER, "hi", 1, null);

        verify(pushService, never())
                .pushMessage(anyLong(), anyString(), anyString(), nullable(Long.class));
    }
}
