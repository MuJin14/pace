package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.dto.websocket.ReadReceiptPushData;
import com.campusrun.server.dto.websocket.WsMessage;
import com.campusrun.server.entity.Friendship;
import com.campusrun.server.entity.Message;
import com.campusrun.server.enums.FriendshipStatus;
import com.campusrun.server.enums.MessageType;
import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.mapper.MessageMapper;
import com.campusrun.server.service.ChatPreferenceService;
import com.campusrun.server.service.MessageService;
import com.campusrun.server.websocket.WebSocketSessionManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

@Service
public class MessageServiceImpl implements MessageService {

    private static final Logger log = LoggerFactory.getLogger(MessageServiceImpl.class);
    private static final int OFFLINE_BATCH = 200;
    private static final int MAX_CONTENT_LENGTH = 2000;
    /** 媒体地址长度上限，与 message.media_url VARCHAR(255) 对齐。 */
    private static final int MAX_MEDIA_URL_LENGTH = 255;
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final MessageMapper messageMapper;
    private final FriendshipMapper friendshipMapper;
    private final WebSocketSessionManager sessionManager;
    private final com.campusrun.server.push.PushService pushService;
    /** 免打扰判断。为 null 时（部分单测）视为「全部不免打扰」。 */
    private final ChatPreferenceService chatPreferenceService;

    /**
     * 查发送者昵称用的 Mapper。
     *
     * <p>用 {@link org.springframework.beans.factory.ObjectProvider} 而不是直接注入：
     * 现有单测是用 5 参构造手写的（传 null），直接注入会让那些测试全部编译不过。
     * 取不到时昵称留空，客户端回退到「新消息」——功能降级但不会崩。
     */
    private final org.springframework.beans.factory.ObjectProvider<com.campusrun.server.mapper.UserMapper>
            userMapperProvider;

    /** 给单测用的 5 参构造：不带昵称查询。 */
    public MessageServiceImpl(MessageMapper messageMapper, FriendshipMapper friendshipMapper,
                              WebSocketSessionManager sessionManager,
                              com.campusrun.server.push.PushService pushService,
                              ChatPreferenceService chatPreferenceService) {
        this(messageMapper, friendshipMapper, sessionManager, pushService,
                chatPreferenceService, null);
    }

    /** Spring 用这个构造器（可空注入 pushService 的兼容构造器见下）。 */
    @org.springframework.beans.factory.annotation.Autowired
    public MessageServiceImpl(MessageMapper messageMapper, FriendshipMapper friendshipMapper,
                              WebSocketSessionManager sessionManager,
                              com.campusrun.server.push.PushService pushService,
                              ChatPreferenceService chatPreferenceService,
                              org.springframework.beans.factory.ObjectProvider<com.campusrun.server.mapper.UserMapper>
                                      userMapperProvider) {
        this.messageMapper = messageMapper;
        this.friendshipMapper = friendshipMapper;
        this.sessionManager = sessionManager;
        this.pushService = pushService;
        this.chatPreferenceService = chatPreferenceService;
        this.userMapperProvider = userMapperProvider;
    }

    /** 兼容构造器（既有单测用，不涉及离线推送与免打扰）。 */
    public MessageServiceImpl(MessageMapper messageMapper, FriendshipMapper friendshipMapper,
                              WebSocketSessionManager sessionManager) {
        this(messageMapper, friendshipMapper, sessionManager, null, null);
    }

    /**
     * 兼容构造器：只关心离线推送、不涉及免打扰的既有单测。
     *
     * <p>chatPreferenceService 传 null 时 {@link #isMuted} 一律返回 false
     * （即「未设置免打扰」），因此推送行为与加免打扰之前完全一致。
     */
    public MessageServiceImpl(MessageMapper messageMapper, FriendshipMapper friendshipMapper,
                              WebSocketSessionManager sessionManager,
                              com.campusrun.server.push.PushService pushService) {
        this(messageMapper, friendshipMapper, sessionManager, pushService, null);
    }

    /**
     * 先落库 → 对方在线则推送并标记已投递，否则留作离线消息。
     */
    @Override
    @Transactional
    public ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content) {
        return sendMessage(senderId, receiverId, content, MessageType.TEXT.getCode(), null);
    }

    @Override
    @Transactional
    public ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content,
                                           Integer type, String mediaUrl) {
        // type 缺省按文本处理：旧客户端只传 receiverId + content，
        // 若这里把 null 当「未知类型」拒绝，老版本 App 会完全发不出消息。
        MessageType messageType = type == null
                ? MessageType.TEXT
                : MessageType.fromCode(type);
        if (messageType == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "不支持的消息类型");
        }

        String normalizedContent = content == null ? null : content.trim();
        String normalizedMedia = mediaUrl == null ? null : mediaUrl.trim();
        if (normalizedMedia != null && normalizedMedia.isEmpty()) {
            normalizedMedia = null;
        }

        // 按类型校验参数，不信任客户端传的组合。
        if (messageType.requiresMedia()) {
            if (normalizedMedia == null) {
                throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID.getCode(),
                        messageType == MessageType.IMAGE ? "图片消息缺少图片地址" : "表情消息缺少资源地址");
            }
            if (normalizedMedia.length() > MAX_MEDIA_URL_LENGTH) {
                throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID.getCode(), "媒体地址过长");
            }
            // 媒体消息不再要求文字；但允许带一句说明，长度同样受限
            if (normalizedContent != null && normalizedContent.length() > MAX_CONTENT_LENGTH) {
                throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID);
            }
        } else {
            if (normalizedContent == null || normalizedContent.isEmpty()) {
                throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID);
            }
            if (normalizedContent.length() > MAX_CONTENT_LENGTH) {
                throw new BusinessException(ErrorCode.MESSAGE_CONTENT_INVALID);
            }
            // 文本消息不允许携带媒体地址：否则可以「文本 + 图片」绕过上面的媒体校验
            normalizedMedia = null;
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
        message.setContent(normalizedContent);
        message.setType(messageType.getCode());
        message.setMediaUrl(normalizedMedia);
        message.setDelivered(0);
        message.setCreatedAt(LocalDateTime.ofInstant(Instant.ofEpochMilli(now), ZONE));
        messageMapper.insert(message);

        ChatMessageResponse response = toResponse(message, now);

        if (sessionManager.isOnline(receiverId)) {
            if (sessionManager.sendToUser(receiverId, new WsMessage("message", response))) {
                message.setDelivered(1);
                messageMapper.updateById(message);
                response.setDelivered(1);
            } else {
                log.warn("消息推送失败，userId={}, messageId={}", receiverId, message.getId());
            }
        }

        // 离线推送：对方**在线时跳过**。
        // 在线时 App 已经通过 WebSocket 收到消息并显示，再弹一条系统通知是重复打扰。
        // 这里只覆盖「App 已关闭 / 被系统挂起」的情况 —— 那正是这套机制存在的意义。
        //
        // 免打扰只拦「推送」，不拦落库与在线送达 ——
        // 用户要的是「别弹通知」，不是「别收消息」。
        if (pushService != null && !sessionManager.isOnline(receiverId)) {
            if (isMuted(receiverId, senderId)) {
                log.debug("对方已对该会话设置免打扰，跳过离线推送，receiverId={}, senderId={}",
                        receiverId, senderId);
            } else {
                pushService.pushMessage(receiverId, pushService.nicknameOf(senderId),
                        pushPreview(messageType, normalizedContent), message.getId());
            }
        }
        return response;
    }

    /** 接收方是否对与发送方的会话免打扰。service 未装配时视为不免打扰。 */
    private boolean isMuted(Long receiverId, Long senderId) {
        return chatPreferenceService != null && chatPreferenceService.isMuted(receiverId, senderId);
    }

    /**
     * 离线通知正文：媒体消息不能让通知栏显示空白。
     *
     * <p>文本则原样返回；图片/表情用可读占位，否则用户只看到一条没有内容的推送。
     */
    private String pushPreview(MessageType type, String content) {
        if (type == MessageType.IMAGE) {
            return "[图片]";
        }
        if (type == MessageType.STICKER) {
            return "[表情]";
        }
        return content;
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
    @Transactional
    public PageResponse<ChatMessageResponse> history(Long userId, Long friendId, Long beforeId, long size) {
        // 打开会话即视为已读：先标记「好友发给我」的未读消息，再查询，使返回的条目带上 readAt
        markConversationRead(userId, friendId);

        long safeSize = Math.min(100, Math.max(1, size));
        long effectiveBefore = beforeId == null ? Long.MAX_VALUE : beforeId;
        List<Message> list = messageMapper.selectHistory(userId, friendId, effectiveBefore, (int) safeSize);
        List<ChatMessageResponse> items = list.stream()
                .map(m -> toResponse(m, toEpochMillis(m.getCreatedAt())))
                .toList();
        return new PageResponse<>(items.size(), 1L, safeSize, items);
    }

    @Override
    @Transactional
    public int markRead(Long userId, List<Long> messageIds) {
        if (userId == null || messageIds == null) {
            return 0;
        }
        List<Long> ids = messageIds.stream().filter(Objects::nonNull).distinct().toList();
        if (ids.isEmpty()) {
            return 0;
        }

        List<Message> messages = messageMapper.selectBatchIds(ids);
        // 只有接收方有权标记：只要有一条消息不是发给当前用户的，整批拒绝，避免越权改写他人消息
        for (Message message : messages) {
            if (!userId.equals(message.getReceiverId())) {
                throw new BusinessException(ErrorCode.FORBIDDEN.getCode(), "只能标记别人发给自己的消息");
            }
        }

        List<Message> unread = messages.stream()
                .filter(message -> message.getReadAt() == null)
                .toList();
        if (unread.isEmpty()) {
            // 已全部读过：幂等返回，不覆盖 readAt、不重复推送
            return 0;
        }

        LocalDateTime now = LocalDateTime.now(ZONE);
        int updated = messageMapper.update(null, new LambdaUpdateWrapper<Message>()
                .in(Message::getId, unread.stream().map(Message::getId).toList())
                .eq(Message::getReceiverId, userId)
                .isNull(Message::getReadAt)
                .set(Message::getReadAt, now));
        if (updated > 0) {
            pushReadReceipt(userId, unread, toEpochMillis(now));
        }
        return updated;
    }

    /**
     * 把 userId 与 friendId 会话中「friendId 发给 userId 且未读」的消息标记为已读，并推送回执。
     */
    private void markConversationRead(Long userId, Long friendId) {
        if (userId == null || friendId == null || userId.equals(friendId)) {
            return;
        }
        List<Message> unread = messageMapper.selectList(new LambdaQueryWrapper<Message>()
                .eq(Message::getReceiverId, userId)
                .eq(Message::getSenderId, friendId)
                .isNull(Message::getReadAt));
        if (unread.isEmpty()) {
            return;
        }

        LocalDateTime now = LocalDateTime.now(ZONE);
        int updated = messageMapper.update(null, new LambdaUpdateWrapper<Message>()
                .in(Message::getId, unread.stream().map(Message::getId).toList())
                .eq(Message::getReceiverId, userId)
                .isNull(Message::getReadAt)
                .set(Message::getReadAt, now));
        if (updated > 0) {
            pushReadReceipt(userId, unread, toEpochMillis(now));
        }
    }

    /**
     * 已读回执按发送方分组推送；对方离线或推送失败仅记录日志，不影响已读落库。
     */
    private void pushReadReceipt(Long readerId, List<Message> readMessages, long readAt) {
        Map<Long, List<Long>> messageIdsBySender = new LinkedHashMap<>();
        for (Message message : readMessages) {
            if (message.getSenderId() == null) {
                continue;
            }
            messageIdsBySender.computeIfAbsent(message.getSenderId(), key -> new ArrayList<>())
                    .add(message.getId());
        }

        for (Map.Entry<Long, List<Long>> entry : messageIdsBySender.entrySet()) {
            Long senderId = entry.getKey();
            if (senderId.equals(readerId)) {
                continue;
            }
            try {
                ReadReceiptPushData payload = new ReadReceiptPushData(
                        readerId, senderId, List.copyOf(entry.getValue()), readAt);
                sessionManager.sendToUser(senderId, new WsMessage(ReadReceiptPushData.TYPE, payload));
            } catch (Exception e) {
                log.warn("已读回执推送失败，senderId={}, readerId={}", senderId, readerId, e);
            }
        }
    }

    private ChatMessageResponse toResponse(Message message, long timestamp) {
        ChatMessageResponse response = new ChatMessageResponse();
        response.setMessageId(message.getId());
        response.setSenderId(message.getSenderId());
        // 带上发送者昵称：客户端弹通知需要「谁发的」，
        // 而它的好友列表在冷启动时可能还没加载（见 ChatMessageResponse 的说明）。
        response.setSenderNickname(nicknameOf(message.getSenderId()));
        response.setReceiverId(message.getReceiverId());
        response.setContent(message.getContent());
        response.setType(message.getType());
        response.setMediaUrl(message.getMediaUrl());
        response.setDelivered(message.getDelivered());
        response.setReadAt(message.getReadAt() == null ? null : toEpochMillis(message.getReadAt()));
        response.setTimestamp(timestamp);
        return response;
    }

    /**
     * 查昵称；查不到返回 null（客户端回退到「新消息」）。
     *
     * <p>失败不抛异常：昵称只是通知标题的一部分，
     * 为了它让发消息失败是本末倒置。
     */
    private String nicknameOf(Long userId) {
        if (userId == null) {
            return null;
        }
        try {
            var mapper = userMapperProvider == null ? null : userMapperProvider.getIfAvailable();
            if (mapper == null) {
                return null;
            }
            var user = mapper.selectById(userId);
            return user == null ? null : user.getNickname();
        } catch (Exception e) {
            log.debug("查询发送者昵称失败，通知标题将回退为「新消息」: {}", e.getMessage());
            return null;
        }
    }

    private long toEpochMillis(LocalDateTime time) {
        if (time == null) {
            return 0L;
        }
        return time.atZone(ZONE).toInstant().toEpochMilli();
    }

    /**
     * 按好友统计未读数，供客户端在登录/回前台时重建红点。
     *
     * <p>用一次 GROUP BY 查询而不是逐个好友查：好友可能有几十个，
     * N 次查询在弱网下会明显拖慢登录后的首屏。
     */
    @Override
    public java.util.Map<Long, Integer> unreadCounts(Long userId) {
        if (userId == null) {
            return java.util.Map.of();
        }

        // ⚠️ 返回的是**完整快照**：所有好友都在里面，未读为 0 的也要给 0。
        //
        // 为什么不能只返回「未读 > 0」的：那样客户端无法区分
        //   「这个好友没有未读了」和「这次请求没查到这个好友」，
        //   于是本地已经记下的红点永远不会被清掉 —— 会积累出
        //   「僵尸红点」：点进去读过、切出去又冒出来。
        //
        // 空响应（拉取失败）由客户端单独处理：仓库层失败时返回空 Map，
        // 客户端对空结果不做删除，避免网络抖动误清红点。
        java.util.Map<Long, Integer> result = new java.util.LinkedHashMap<>();
        for (Long friendId : friendshipMapper.selectAcceptedFriendIds(userId)) {
            if (friendId != null) {
                result.put(friendId, 0);
            }
        }
        for (java.util.Map<String, Object> row : messageMapper.countUnreadBySender(userId)) {
            Object sender = row.get("senderId");
            Object cnt = row.get("cnt");
            if (sender == null || cnt == null) {
                continue;
            }
            long senderId = ((Number) sender).longValue();
            int count = ((Number) cnt).intValue();
            // 未读可能来自已解除好友关系的人（历史会话），也要保留，
            // 否则那条会话的红点会凭空消失。
            result.put(senderId, count > 0 ? count : 0);
        }
        return result;
    }
}
