package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.entity.Friendship;
import com.campusrun.server.entity.Message;
import com.campusrun.server.enums.FriendshipStatus;
import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.mapper.MessageMapper;
import com.campusrun.server.service.MessageService;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

@Service
public class MessageServiceImpl implements MessageService {

    private static final int OFFLINE_BATCH = 200;
    private static final int MAX_CONTENT_LENGTH = 2000;
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final MessageMapper messageMapper;
    private final FriendshipMapper friendshipMapper;
    private final WebSocketSessionManager sessionManager;

    public MessageServiceImpl(MessageMapper messageMapper, FriendshipMapper friendshipMapper,
                              WebSocketSessionManager sessionManager) {
        this.messageMapper = messageMapper;
        this.friendshipMapper = friendshipMapper;
        this.sessionManager = sessionManager;
    }

    @Override
    @Transactional
    public ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content) {
        if (content == null || content.isBlank()) {
            throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID);
        }
        if (content.length() > MAX_CONTENT_LENGTH) {
            throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID);
        }
        if (senderId.equals(receiverId)) {
            throw new BusinessException(ErrorCode.FRIEND_NOT_FOUND);
        }

        Long friendCount = friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, senderId)
                .eq(Friendship::getFriendId, receiverId)
                .eq(Friendship::getStatus, FriendshipStatus.ACCEPTED.getCode()));
        if (friendCount == null || friendCount == 0) {
            throw new BusinessException(ErrorCode.FRIEND_NOT_FOUND);
        }

        long now = System.currentTimeMillis();
        Message message = new Message();
        message.setSenderId(senderId);
        message.setReceiverId(receiverId);
        message.setContent(content);
        message.setType(1);
        message.setDelivered(0);
        message.setCreatedAt(LocalDateTime.ofInstant(Instant.ofEpochMilli(now), ZONE));
        messageMapper.insert(message);

        ChatMessageResponse response = toResponse(message, now);

        if (sessionManager.isOnline(receiverId)
                && sessionManager.sendToUser(receiverId, new WsMessage("message", response))) {
            message.setDelivered(1);
            messageMapper.updateById(message);
            response.setDelivered(1);
        }
        return response;
    }

    @Override
    public void pushOfflineMessages(Long userId) {
        while (true) {
            List<Message> batch = messageMapper.selectOffline(userId, OFFLINE_BATCH);
            if (batch.isEmpty()) {
                break;
            }
            List<Long> successIds = new ArrayList<>();
            for (Message message : batch) {
                ChatMessageResponse response = toResponse(message, toEpochMillis(message.getCreatedAt()));
                if (sessionManager.sendToUser(userId, new WsMessage("message", response))) {
                    successIds.add(message.getId());
                }
            }
            if (!successIds.isEmpty()) {
                messageMapper.update(null, new LambdaUpdateWrapper<Message>()
                        .in(Message::getId, successIds)
                        .eq(Message::getDelivered, 0)
                        .set(Message::getDelivered, 1));
            }
            if (batch.size() < OFFLINE_BATCH) {
                break;
            }
        }
    }

    @Override
    public PageResponse<ChatMessageResponse> history(Long userId, Long friendId, Long beforeId, long size) {
        long safeSize = Math.min(100, Math.max(1, size));
        long effectiveBefore = beforeId == null ? Long.MAX_VALUE : beforeId;
        List<Message> list = messageMapper.selectHistory(userId, friendId, effectiveBefore, (int) safeSize);
        List<ChatMessageResponse> items = list.stream()
                .map(m -> toResponse(m, toEpochMillis(m.getCreatedAt())))
                .toList();
        return new PageResponse<>(items.size(), 1L, safeSize, items);
    }

    private ChatMessageResponse toResponse(Message message, long timestamp) {
        ChatMessageResponse response = new ChatMessageResponse();
        response.setMessageId(message.getId());
        response.setSenderId(message.getSenderId());
        response.setReceiverId(message.getReceiverId());
        response.setContent(message.getContent());
        response.setType(message.getType());
        response.setDelivered(message.getDelivered());
        response.setTimestamp(timestamp);
        return response;
    }

    private long toEpochMillis(LocalDateTime time) {
        if (time == null) {
            return 0L;
        }
        return time.atZone(ZONE).toInstant().toEpochMilli();
    }
}
