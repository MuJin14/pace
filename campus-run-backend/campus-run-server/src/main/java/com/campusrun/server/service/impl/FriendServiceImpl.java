package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.FriendRequestResponse;
import com.campusrun.server.dto.response.UserBriefResponse;
import com.campusrun.server.dto.websocket.FriendAcceptedPushData;
import com.campusrun.server.dto.websocket.FriendDeletedPushData;
import com.campusrun.server.dto.websocket.FriendRequestPushData;
import com.campusrun.server.entity.Friendship;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.FriendshipStatus;
import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.event.FriendAcceptedEvent;
import com.campusrun.server.event.FriendDeletedEvent;
import com.campusrun.server.event.FriendRequestEvent;
import com.campusrun.server.service.FriendService;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
public class FriendServiceImpl implements FriendService {

    private final FriendshipMapper friendshipMapper;
    private final UserMapper userMapper;
    private final ApplicationEventPublisher eventPublisher;

    public FriendServiceImpl(FriendshipMapper friendshipMapper, UserMapper userMapper,
                            ApplicationEventPublisher eventPublisher) {
        this.friendshipMapper = friendshipMapper;
        this.userMapper = userMapper;
        this.eventPublisher = eventPublisher;
    }

    @Override
    public PageResponse<UserBriefResponse> search(Long userId, String keyword, long page, long size) {
        if (keyword == null || keyword.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "搜索关键词不能为空");
        }
        long safePage = Math.max(1, page);
        long safeSize = Math.min(100, Math.max(1, size));
        long offset = (safePage - 1) * safeSize;

        String kw = keyword.trim();
        long total = friendshipMapper.countSearch(userId, kw);
        List<UserBriefResponse> list = friendshipMapper.searchUsers(userId, kw, offset, safeSize);
        return new PageResponse<>(total, safePage, safeSize, list);
    }

    /**
     * 若对方已向你发起 PENDING 申请，事务内自动接受，双方立即成为好友。
     */
    @Override
    @Transactional
    public void sendRequest(Long userId, Long targetUserId) {
        if (userId.equals(targetUserId)) {
            throw new BusinessException(ErrorCode.CANNOT_FRIEND_SELF);
        }
        User target = userMapper.selectById(targetUserId);
        if (target == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }

        Long existing = friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, targetUserId));
        if (existing != null && existing > 0) {
            throw new BusinessException(ErrorCode.FRIEND_REQUEST_EXISTS);
        }

        // 反向已存在 PENDING 申请：事务内自动接受，双方立即成为好友
        Friendship reverse = friendshipMapper.selectOne(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, targetUserId)
                .eq(Friendship::getFriendId, userId)
                .eq(Friendship::getStatus, FriendshipStatus.PENDING.getCode()));
        if (reverse != null) {
            reverse.setStatus(FriendshipStatus.ACCEPTED.getCode());
            friendshipMapper.updateById(reverse);
            insertAccepted(userId, targetUserId);
            publishFriendAccepted(userId, targetUserId);
            return;
        }

        Friendship request = new Friendship();
        request.setUserId(userId);
        request.setFriendId(targetUserId);
        request.setStatus(FriendshipStatus.PENDING.getCode());
        friendshipMapper.insert(request);
        publishFriendRequest(request.getId(), userId, targetUserId);
    }

    @Override
    @Transactional
    public void acceptRequest(Long userId, Long requestId) {
        Friendship request = friendshipMapper.selectById(requestId);
        if (request == null || !isPending(request) || !userId.equals(request.getFriendId())) {
            throw new BusinessException(ErrorCode.FRIEND_REQUEST_NOT_FOUND);
        }

        request.setStatus(FriendshipStatus.ACCEPTED.getCode());
        friendshipMapper.updateById(request);

        // 建立反向 ACCEPTED（已存在则修正为 ACCEPTED）
        Friendship reverse = friendshipMapper.selectOne(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, request.getUserId()));
        if (reverse == null) {
            insertAccepted(userId, request.getUserId());
        } else if (!isAccepted(reverse)) {
            reverse.setStatus(FriendshipStatus.ACCEPTED.getCode());
            friendshipMapper.updateById(reverse);
        }

        publishFriendAccepted(userId, request.getUserId());
    }

    @Override
    @Transactional
    public void rejectRequest(Long userId, Long requestId) {
        Friendship request = friendshipMapper.selectById(requestId);
        if (request == null || !isPending(request) || !userId.equals(request.getFriendId())) {
            throw new BusinessException(ErrorCode.FRIEND_REQUEST_NOT_FOUND);
        }
        friendshipMapper.deleteById(requestId);
    }

    @Override
    public List<FriendRequestResponse> incomingRequests(Long userId) {
        return friendshipMapper.selectIncoming(userId);
    }

    @Override
    public List<FriendItemResponse> friendList(Long userId) {
        return friendshipMapper.selectFriends(userId);
    }

    @Override
    @Transactional
    public void deleteFriend(Long userId, Long friendId) {
        Long count = friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, friendId)
                .eq(Friendship::getStatus, FriendshipStatus.ACCEPTED.getCode()));
        if (count == null || count == 0) {
            throw new BusinessException(ErrorCode.FRIEND_NOT_FOUND);
        }
        friendshipMapper.delete(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, friendId));
        friendshipMapper.delete(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, friendId)
                .eq(Friendship::getFriendId, userId));

        publishFriendDeleted(userId, friendId);
    }

    private void publishFriendRequest(Long requestId, Long fromUserId, Long targetUserId) {
        User from = userMapper.selectById(fromUserId);
        FriendRequestPushData data = new FriendRequestPushData();
        data.setRequestId(requestId);
        data.setFromUserId(fromUserId);
        data.setFromUniqueId(from.getUniqueId());
        data.setFromNickname(from.getNickname());
        data.setFromAvatarUrl(from.getAvatarUrl());
        data.setCreatedAt(LocalDateTime.now());
        eventPublisher.publishEvent(new FriendRequestEvent(targetUserId, data));
    }

    private void publishFriendAccepted(Long friendUserId, Long targetUserId) {
        User me = userMapper.selectById(friendUserId);
        FriendAcceptedPushData data = new FriendAcceptedPushData();
        data.setFriendUserId(friendUserId);
        data.setFriendUniqueId(me.getUniqueId());
        data.setFriendNickname(me.getNickname());
        data.setFriendAvatarUrl(me.getAvatarUrl());
        eventPublisher.publishEvent(new FriendAcceptedEvent(targetUserId, data));
    }

    private void publishFriendDeleted(Long deletedByUserId, Long targetUserId) {
        FriendDeletedPushData data = new FriendDeletedPushData();
        data.setFriendUserId(deletedByUserId);
        eventPublisher.publishEvent(new FriendDeletedEvent(targetUserId, data));
    }

    private void insertAccepted(Long userId, Long friendId) {
        Friendship friendship = new Friendship();
        friendship.setUserId(userId);
        friendship.setFriendId(friendId);
        friendship.setStatus(FriendshipStatus.ACCEPTED.getCode());
        friendshipMapper.insert(friendship);
    }

    private boolean isPending(Friendship friendship) {
        return Integer.valueOf(FriendshipStatus.PENDING.getCode()).equals(friendship.getStatus());
    }

    private boolean isAccepted(Friendship friendship) {
        return Integer.valueOf(FriendshipStatus.ACCEPTED.getCode()).equals(friendship.getStatus());
    }
}
