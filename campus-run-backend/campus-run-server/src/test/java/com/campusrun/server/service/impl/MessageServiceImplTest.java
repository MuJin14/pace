package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.Message;
import com.campusrun.server.mapper.MessageMapper;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.FriendService;
import com.campusrun.server.service.MessageService;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
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
}
