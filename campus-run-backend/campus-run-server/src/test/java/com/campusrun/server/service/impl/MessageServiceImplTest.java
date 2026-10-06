package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.dto.websocket.ReadReceiptPushData;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.entity.Message;
import com.campusrun.server.mapper.MessageMapper;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.FriendService;
import com.campusrun.server.service.MessageService;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class MessageServiceImplTest {

    @Autowired
    private MessageService messageService;

    @Autowired
    private FriendService friendService;

    @Autowired
    private AuthService authService;

    @Autowired
    private MessageMapper messageMapper;

    @MockBean
    private WebSocketSessionManager sessionManager;

    private Long registerUser(String phone, String nickname) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname(nickname);
        LoginResponse resp = authService.register(req);
        return resp.getUserId();
    }

    private void makeFriends(Long a, Long b) {
        friendService.sendRequest(a, b);
        friendService.sendRequest(b, a);
    }

    private void insertOffline(Long senderId, Long receiverId, int count) {
        for (int i = 0; i < count; i++) {
            Message m = new Message();
            m.setSenderId(senderId);
            m.setReceiverId(receiverId);
            m.setContent("msg" + i);
            m.setType(1);
            m.setDelivered(0);
            m.setCreatedAt(LocalDateTime.now());
            messageMapper.insert(m);
        }
    }

    private long countUndelivered(Long receiverId) {
        return messageMapper.selectCount(new LambdaQueryWrapper<Message>()
                .eq(Message::getReceiverId, receiverId)
                .eq(Message::getDelivered, 0));
    }

    @Test
    void sendMessage_whenReceiverOffline_persistsWithDelivered0() {
        Long a = registerUser("13920000101", "甲");
        Long b = registerUser("13920000102", "乙");
        makeFriends(a, b);

        when(sessionManager.isOnline(b)).thenReturn(false);

        ChatMessageResponse resp = messageService.sendMessage(a, b, "你好");

        Message saved = messageMapper.selectById(resp.getMessageId());
        assertEquals(0, saved.getDelivered());
        assertEquals(a, saved.getSenderId());
        assertEquals(b, saved.getReceiverId());
        // 新消息未读：不返回 readAt
        assertNull(saved.getReadAt());
        assertNull(resp.getReadAt());
    }

    @Test
    void sendMessage_whenReceiverOnline_marksDelivered1() {
        Long a = registerUser("13920000103", "甲");
        Long b = registerUser("13920000104", "乙");
        makeFriends(a, b);

        when(sessionManager.isOnline(b)).thenReturn(true);
        when(sessionManager.sendToUser(eq(b), any())).thenReturn(true);

        ChatMessageResponse resp = messageService.sendMessage(a, b, "在吗");

        assertEquals(1, messageMapper.selectById(resp.getMessageId()).getDelivered());
        assertEquals(1, resp.getDelivered());
    }

    @Test
    void sendMessage_toNonFriend_throwsFriendNotFound() {
        Long a = registerUser("13920000105", "甲");
        Long b = registerUser("13920000106", "乙");

        BusinessException e = assertThrows(BusinessException.class,
                () -> messageService.sendMessage(a, b, "你好"));
        assertEquals(ErrorCode.FRIEND_NOT_FOUND.getCode(), e.getCode());
    }

    @Test
    void sendMessage_emptyContent_throws() {
        Long a = registerUser("13920000107", "甲");
        Long b = registerUser("13920000108", "乙");
        makeFriends(a, b);

        assertThrows(BusinessException.class, () -> messageService.sendMessage(a, b, ""));
        assertThrows(BusinessException.class, () -> messageService.sendMessage(a, b, null));
    }

    @Test
    void sendMessage_tooLongContent_throws() {
        Long a = registerUser("13920000109", "甲");
        Long b = registerUser("13920000110", "乙");
        makeFriends(a, b);

        String longContent = "x".repeat(2001);
        assertThrows(BusinessException.class, () -> messageService.sendMessage(a, b, longContent));
    }

    @Test
    void pushOfflineMessages_marksAllDelivered() {
        Long a = registerUser("13920000111", "甲");
        Long b = registerUser("13920000112", "乙");
        insertOffline(a, b, 5);

        when(sessionManager.sendToUser(eq(b), any())).thenReturn(true);

        messageService.pushOfflineMessages(b);

        assertEquals(0, countUndelivered(b));
    }

    @Test
    void pushOfflineMessages_whenMoreThan200_loopsUntilEmpty() {
        Long a = registerUser("13920000113", "甲");
        Long b = registerUser("13920000114", "乙");
        insertOffline(a, b, 250);

        when(sessionManager.sendToUser(eq(b), any())).thenReturn(true);

        messageService.pushOfflineMessages(b);

        assertEquals(0, countUndelivered(b));
    }

    @Test
    void pushOfflineMessages_whenSendFails_leavesUndelivered() {
        Long a = registerUser("13920000115", "甲");
        Long b = registerUser("13920000116", "乙");
        insertOffline(a, b, 3);

        when(sessionManager.sendToUser(eq(b), any())).thenReturn(false);

        messageService.pushOfflineMessages(b);

        assertEquals(3, countUndelivered(b));
    }

    @Test
    void history_returnsBidirectionalDescOrder() {
        Long a = registerUser("13920000117", "甲");
        Long b = registerUser("13920000118", "乙");

        Long m1 = insertMessage(a, b, "a->b");
        Long m2 = insertMessage(b, a, "b->a");
        Long m3 = insertMessage(a, b, "a->b again");

        PageResponse<ChatMessageResponse> page = messageService.history(a, b, null, 20);
        List<ChatMessageResponse> items = page.getList();

        assertEquals(3, items.size());
        assertEquals(m3, items.get(0).getMessageId());
        assertEquals(m2, items.get(1).getMessageId());
        assertEquals(m1, items.get(2).getMessageId());
    }

    // ---------- 已读回执 ----------

    @Test
    void markRead_marksOnlyMessagesAddressedToMe() {
        Long a = registerUser("13920000201", "甲");
        Long b = registerUser("13920000202", "乙");
        makeFriends(a, b);

        Long a2b1 = insertMessage(a, b, "a->b 1");
        Long a2b2 = insertMessage(a, b, "a->b 2");
        Long b2a = insertMessage(b, a, "b->a");

        int marked = messageService.markRead(b, List.of(a2b1, a2b2));

        assertEquals(2, marked);
        assertNotNull(messageMapper.selectById(a2b1).getReadAt());
        assertNotNull(messageMapper.selectById(a2b2).getReadAt());
        // b 自己发出的消息不能被自己标记已读
        assertNull(messageMapper.selectById(b2a).getReadAt());
    }

    @Test
    void markRead_isIdempotent_andPushesReceiptOnce() {
        Long a = registerUser("13920000203", "甲");
        Long b = registerUser("13920000204", "乙");
        makeFriends(a, b);

        Long a2b1 = insertMessage(a, b, "a->b 1");
        Long a2b2 = insertMessage(a, b, "a->b 2");

        assertEquals(2, messageService.markRead(b, List.of(a2b1, a2b2)));
        LocalDateTime firstReadAt = messageMapper.selectById(a2b1).getReadAt();
        assertNotNull(firstReadAt);

        // 重复标记：不再改写 readAt，也不再重复推送
        assertEquals(0, messageService.markRead(b, List.of(a2b1, a2b2)));
        assertEquals(firstReadAt, messageMapper.selectById(a2b1).getReadAt());
        verify(sessionManager, times(1)).sendToUser(eq(a), any());
    }

    @Test
    void markRead_bySender_rejectedWithForbidden() {
        Long a = registerUser("13920000205", "甲");
        Long b = registerUser("13920000206", "乙");
        makeFriends(a, b);

        Long a2b = insertMessage(a, b, "a->b");

        // a 是发送方，无权把自己的消息标记为已读
        BusinessException e = assertThrows(BusinessException.class,
                () -> messageService.markRead(a, List.of(a2b)));
        assertEquals(ErrorCode.FORBIDDEN.getCode(), e.getCode());
        assertNull(messageMapper.selectById(a2b).getReadAt());
        verify(sessionManager, never()).sendToUser(any(), any());
    }

    @Test
    void markRead_mixedBatch_rejectedAtomically() {
        Long a = registerUser("13920000207", "甲");
        Long b = registerUser("13920000208", "乙");
        makeFriends(a, b);

        Long a2b = insertMessage(a, b, "a->b");
        Long b2a = insertMessage(b, a, "b->a");

        assertThrows(BusinessException.class,
                () -> messageService.markRead(b, List.of(a2b, b2a)));

        // 整批拒绝：合法的那条也不能被标记
        assertNull(messageMapper.selectById(a2b).getReadAt());
        assertNull(messageMapper.selectById(b2a).getReadAt());
    }

    @Test
    void markRead_pushesReadReceiptToPeer() {
        Long a = registerUser("13920000209", "甲");
        Long b = registerUser("13920000210", "乙");
        makeFriends(a, b);

        Long a2b1 = insertMessage(a, b, "a->b 1");
        Long a2b2 = insertMessage(a, b, "a->b 2");

        when(sessionManager.sendToUser(eq(a), any())).thenReturn(true);

        messageService.markRead(b, List.of(a2b1, a2b2));

        ArgumentCaptor<WsMessage> captor = ArgumentCaptor.forClass(WsMessage.class);
        verify(sessionManager).sendToUser(eq(a), captor.capture());
        WsMessage wsMessage = captor.getValue();
        assertEquals(ReadReceiptPushData.TYPE, wsMessage.getType());
        assertEquals("read_receipt", wsMessage.getType());

        ReadReceiptPushData data = (ReadReceiptPushData) wsMessage.getData();
        assertEquals(b, data.getReaderId());
        assertEquals(a, data.getFriendId());
        assertEquals(Set.of(a2b1, a2b2), Set.copyOf(data.getMessageIds()));
        assertTrue(data.getReadAt() > 0);
    }

    @Test
    void markRead_whenPeerOffline_doesNotThrow() {
        Long a = registerUser("13920000211", "甲");
        Long b = registerUser("13920000212", "乙");
        makeFriends(a, b);

        Long a2b = insertMessage(a, b, "a->b");
        // 对方离线/推送异常都不应影响已读落库
        when(sessionManager.sendToUser(any(), any())).thenThrow(new IllegalStateException("offline"));

        assertEquals(1, messageService.markRead(b, List.of(a2b)));
        assertNotNull(messageMapper.selectById(a2b).getReadAt());
    }

    @Test
    void markRead_emptyOrNullIds_returnsZero() {
        Long a = registerUser("13920000213", "甲");
        Long b = registerUser("13920000214", "乙");
        makeFriends(a, b);
        insertMessage(a, b, "a->b");

        assertEquals(0, messageService.markRead(b, null));
        assertEquals(0, messageService.markRead(b, List.of()));
        verify(sessionManager, never()).sendToUser(any(), any());
    }

    @Test
    void markRead_unknownIds_returnsZero() {
        Long a = registerUser("13920000215", "甲");
        Long b = registerUser("13920000216", "乙");
        makeFriends(a, b);

        assertEquals(0, messageService.markRead(b, List.of(999999L)));
        verify(sessionManager, never()).sendToUser(any(), any());
    }

    @Test
    void history_marksReceivedMessagesRead_andPushesReceipt() {
        Long a = registerUser("13920000217", "甲");
        Long b = registerUser("13920000218", "乙");
        makeFriends(a, b);

        Long a2b = insertMessage(a, b, "a->b");
        Long b2a = insertMessage(b, a, "b->a");

        PageResponse<ChatMessageResponse> page = messageService.history(b, a, null, 20);

        // b 打开会话：a 发来的消息自动已读，b 自己发出的仍为未读
        assertNotNull(messageMapper.selectById(a2b).getReadAt());
        assertNull(messageMapper.selectById(b2a).getReadAt());

        // 返回体同步带上 readAt，前端据此渲染已读
        ChatMessageResponse received = page.getList().stream()
                .filter(item -> item.getMessageId().equals(a2b)).findFirst().orElseThrow();
        ChatMessageResponse sent = page.getList().stream()
                .filter(item -> item.getMessageId().equals(b2a)).findFirst().orElseThrow();
        assertTrue(received.getReadAt() != null && received.getReadAt() > 0);
        assertNull(sent.getReadAt());

        // 回执推送给原发送者 a
        verify(sessionManager).sendToUser(eq(a), any());
    }

    @Test
    void history_whenNothingUnread_doesNotPushReceipt() {
        Long a = registerUser("13920000219", "甲");
        Long b = registerUser("13920000220", "乙");
        makeFriends(a, b);

        Long a2b = insertMessage(a, b, "a->b");
        Long b2a = insertMessage(b, a, "b->a");
        // 预先置为已读
        Message read = messageMapper.selectById(a2b);
        read.setReadAt(LocalDateTime.now().minusMinutes(5));
        messageMapper.updateById(read);
        LocalDateTime presetReadAt = messageMapper.selectById(a2b).getReadAt();
        assertNotNull(presetReadAt);

        messageService.history(b, a, null, 20);

        // 已读的消息不会被重复改写，b 自己发出的消息也不受影响
        assertEquals(presetReadAt, messageMapper.selectById(a2b).getReadAt());
        assertNull(messageMapper.selectById(b2a).getReadAt());
        // 没有任何新标记 → 不推送回执
        verify(sessionManager, never()).sendToUser(eq(a), any());
    }

    private Long insertMessage(Long senderId, Long receiverId, String content) {
        Message m = new Message();
        m.setSenderId(senderId);
        m.setReceiverId(receiverId);
        m.setContent(content);
        m.setType(1);
        m.setDelivered(1);
        m.setCreatedAt(LocalDateTime.now());
        messageMapper.insert(m);
        return m.getId();
    }

    // ── 富媒体消息：type / mediaUrl 的服务端校验 ─────────────────────
    //
    // 关键原则：**类型与参数的匹配由服务端强制**，不信任客户端传来的组合。
    // 否则客户端可以「type=1 + 带 mediaUrl」绕过媒体校验，
    // 或者「type=2 但不给地址」造出一条永远加载不出来的空图片消息。

    @Test
    void sendImageMessage_persistsTypeAndMediaUrl() {
        Long a = registerUser("13920000201", "甲");
        Long b = registerUser("13920000202", "乙");
        makeFriends(a, b);
        when(sessionManager.isOnline(b)).thenReturn(false);

        ChatMessageResponse resp = messageService.sendMessage(
                a, b, null, 2, "http://host/uploads/chat/x.jpg");

        Message saved = messageMapper.selectById(resp.getMessageId());
        assertEquals(2, saved.getType());
        assertEquals("http://host/uploads/chat/x.jpg", saved.getMediaUrl());
        assertNull(saved.getContent(), "图片消息可以没有文字");
        assertEquals(2, resp.getType());
        assertEquals("http://host/uploads/chat/x.jpg", resp.getMediaUrl());
    }

    @Test
    void sendImageMessage_withoutMediaUrl_throws() {
        Long a = registerUser("13920000203", "甲");
        Long b = registerUser("13920000204", "乙");
        makeFriends(a, b);

        assertThrows(BusinessException.class,
                () -> messageService.sendMessage(a, b, null, 2, null));
        assertThrows(BusinessException.class,
                () -> messageService.sendMessage(a, b, null, 2, "   "));
    }

    @Test
    void sendStickerMessage_requiresMediaToo() {
        Long a = registerUser("13920000205", "甲");
        Long b = registerUser("13920000206", "乙");
        makeFriends(a, b);

        assertThrows(BusinessException.class,
                () -> messageService.sendMessage(a, b, null, 3, null));
    }

    @Test
    void sendTextMessage_withMediaUrl_isRejectedAndDropped() {
        Long a = registerUser("13920000207", "甲");
        Long b = registerUser("13920000208", "乙");
        makeFriends(a, b);
        when(sessionManager.isOnline(b)).thenReturn(false);

        // 文本消息带 mediaUrl：不能被保存成「文本 + 图片」的混合体，
        // 否则等于绕过了媒体消息的必填校验。
        ChatMessageResponse resp = messageService.sendMessage(
                a, b, "看这个", 1, "http://host/uploads/chat/x.jpg");

        Message saved = messageMapper.selectById(resp.getMessageId());
        assertEquals(1, saved.getType());
        assertNull(saved.getMediaUrl(), "文本消息的 mediaUrl 必须被丢弃");
        assertEquals("看这个", saved.getContent());
    }

    @Test
    void sendMessage_withUnknownType_throws() {
        Long a = registerUser("13920000209", "甲");
        Long b = registerUser("13920000210", "乙");
        makeFriends(a, b);

        assertThrows(BusinessException.class,
                () -> messageService.sendMessage(a, b, "hi", 99, null));
    }

    @Test
    void sendMessage_withoutType_defaultsToText() {
        Long a = registerUser("13920000211", "甲");
        Long b = registerUser("13920000212", "乙");
        makeFriends(a, b);
        when(sessionManager.isOnline(b)).thenReturn(false);

        // 旧客户端不传 type：必须仍能正常发文本，不能因为加了富媒体就发不出消息
        ChatMessageResponse resp = messageService.sendMessage(a, b, "你好", null, null);

        Message saved = messageMapper.selectById(resp.getMessageId());
        assertEquals(1, saved.getType());
        assertEquals("你好", saved.getContent());
    }

    @Test
    void sendImageMessage_tooLongMediaUrl_throws() {
        Long a = registerUser("13920000213", "甲");
        Long b = registerUser("13920000214", "乙");
        makeFriends(a, b);

        String tooLong = "http://host/" + "x".repeat(300) + ".jpg";
        assertThrows(BusinessException.class,
                () -> messageService.sendMessage(a, b, null, 2, tooLong));
    }
}