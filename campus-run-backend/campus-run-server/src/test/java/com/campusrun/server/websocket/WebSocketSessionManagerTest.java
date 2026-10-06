package com.campusrun.server.websocket;

import com.campusrun.server.dto.websocket.WsMessage;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WebSocketSessionManagerTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final WebSocketSessionManager manager = new WebSocketSessionManager(objectMapper);

    private WebSocketSession openSession() {
        WebSocketSession session = mock(WebSocketSession.class);
        when(session.isOpen()).thenReturn(true);
        return session;
    }

    @Test
    void addAndIsOnline() {
        WebSocketSession session = openSession();

        manager.addSession(1L, session);

        assertTrue(manager.isOnline(1L));
    }

    @Test
    void removeSession_makesOffline() {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);

        manager.removeSession(1L, session);

        assertFalse(manager.isOnline(1L));
    }

    @Test
    void sendToUser_whenOffline_returnsFalse() {
        assertFalse(manager.sendToUser(1L, new WsMessage("pong", null)));
    }

    @Test
    void sendToUser_whenOnline_sendsJsonAndReturnsTrue() throws Exception {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);

        boolean sent = manager.sendToUser(1L, new WsMessage("pong", null));

        assertTrue(sent);
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(captor.capture());
        assertTrue(captor.getValue().getPayload().contains("\"type\":\"pong\""));
    }

    @Test
    void sendToUser_closedSession_returnsFalse() {
        WebSocketSession session = mock(WebSocketSession.class);
        when(session.isOpen()).thenReturn(false);
        manager.addSession(1L, session);

        assertFalse(manager.sendToUser(1L, new WsMessage("pong", null)));
    }

    @Test
    void sweep_removesIdleSessionEvenIfCloseFails() throws Exception {
        WebSocketSession session = openSession();
        doThrow(new IOException("boom")).when(session).close(any(CloseStatus.class));
        manager.addSession(1L, session);

        Thread.sleep(30);
        manager.sweep(1);

        assertFalse(manager.isOnline(1L));
    }

    /**
     * ⚠️ 这条是「红点延迟」问题的核心断言。
     *
     * <p>sweep 只从 Map 里删掉会话是不够的：客户端的 TCP 连接不会收到任何通知，
     * 它不会重连，也就不会去补拉未读数 —— 表现就是「消息到了，红点很久才出现」。
     *
     * <p>必须先 {@code close()}，让客户端收到 onDone/onError 主动重连。
     * 这个断言在实现退化成「只 remove」时会失败。
     */
    @Test
    void sweep_mustCloseSessionSoClientLearnsToReconnect() throws Exception {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);

        Thread.sleep(30);
        manager.sweep(1);

        ArgumentCaptor<CloseStatus> status = ArgumentCaptor.forClass(CloseStatus.class);
        verify(session).close(status.capture());
        assertFalse(manager.isOnline(1L));
    }

    @Test
    void sweep_leavesRecentlyActiveSessionAlone() throws Exception {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);
        manager.touch(1L);

        // 阈值远大于「刚刚 touch 过」的时间差
        manager.sweep(60_000);

        assertTrue(manager.isOnline(1L), "刚有心跳的连接不能被杀掉");
        verify(session, never()).close(any(CloseStatus.class));
    }

    /**
     * 活跃时间缺失时也要清理。
     *
     * <p>正常情况下 {@code addSession} 会写入活跃时间；缺失说明状态已经不一致，
     * 留着它只会让 {@code sendToUser} 以为用户在线（消息投进黑洞）。
     */
    @Test
    void sweep_cleansSessionWithoutActivityRecord() throws Exception {
        WebSocketSession session = openSession();
        manager.addSession(1L, session);
        // 人为制造「有会话但没有活跃记录」
        manager.removeActivityForTest(1L);

        manager.sweep(60_000);

        assertFalse(manager.isOnline(1L));
    }
}
