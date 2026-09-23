package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.FriendRequestResponse;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.dto.response.UserBriefResponse;
import com.campusrun.server.entity.Friendship;
import com.campusrun.server.enums.FriendshipStatus;
import com.campusrun.server.event.FriendAcceptedEvent;
import com.campusrun.server.event.FriendDeletedEvent;
import com.campusrun.server.event.FriendRequestEvent;
import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.FriendService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.event.EventListener;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class FriendServiceImplTest {

    @Autowired
    private FriendService friendService;

    @Autowired
    private AuthService authService;

    @Autowired
    private FriendshipMapper friendshipMapper;

    @Autowired
    private FriendEventCapture events;

    @BeforeEach
    void resetEvents() {
        events.clear();
    }

    private LoginResponse registerUser(String phone, String nickname) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname(nickname);
        return authService.register(req);
    }

    private Friendship row(Long userId, Long friendId) {
        return friendshipMapper.selectOne(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, friendId));
    }

    private long count(Long userId, Long friendId) {
        return friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, friendId));
    }

    private void makeFriends(Long a, Long b) {
        friendService.sendRequest(a, b);
        Long requestId = row(a, b).getId();
        friendService.acceptRequest(b, requestId);
    }

    @Test
    void sendRequest_createsPendingRow() {
        Long a = registerUser("13910000101", "甲").getUserId();
        Long b = registerUser("13910000102", "乙").getUserId();

        friendService.sendRequest(a, b);

        Friendship f = row(a, b);
        assertNotNull(f);
        assertEquals(FriendshipStatus.PENDING.getCode(), f.getStatus());
    }

    @Test
    void sendRequest_toSelf_throwsCannotFriendSelf() {
        Long a = registerUser("13910000103", "甲").getUserId();

        BusinessException e = assertThrows(BusinessException.class,
                () -> friendService.sendRequest(a, a));
        assertEquals(ErrorCode.CANNOT_FRIEND_SELF.getCode(), e.getCode());
    }

    @Test
    void sendRequest_duplicate_throwsRequestExists() {
        Long a = registerUser("13910000104", "甲").getUserId();
        Long b = registerUser("13910000105", "乙").getUserId();

        friendService.sendRequest(a, b);
        assertThrows(BusinessException.class, () -> friendService.sendRequest(a, b));
    }

    @Test
    void sendRequest_targetNotExist_throwsUserNotFound() {
        Long a = registerUser("13910000106", "甲").getUserId();

        BusinessException e = assertThrows(BusinessException.class,
                () -> friendService.sendRequest(a, 999999L));
        assertEquals(ErrorCode.USER_NOT_FOUND.getCode(), e.getCode());
    }

    @Test
    void sendRequest_whenReversePendingExists_autoAccepts() {
        Long a = registerUser("13910000107", "甲").getUserId();
        Long b = registerUser("13910000108", "乙").getUserId();

        friendService.sendRequest(b, a);
        friendService.sendRequest(a, b);

        assertEquals(FriendshipStatus.ACCEPTED.getCode(), row(a, b).getStatus());
        assertEquals(FriendshipStatus.ACCEPTED.getCode(), row(b, a).getStatus());
    }

    @Test
    void acceptRequest_createsBothAcceptedRows() {
        Long a = registerUser("13910000109", "甲").getUserId();
        Long b = registerUser("13910000110", "乙").getUserId();

        friendService.sendRequest(a, b);
        Long requestId = row(a, b).getId();
        friendService.acceptRequest(b, requestId);

        assertEquals(FriendshipStatus.ACCEPTED.getCode(), row(a, b).getStatus());
        assertEquals(FriendshipStatus.ACCEPTED.getCode(), row(b, a).getStatus());
    }

    @Test
    void acceptRequest_requestNotExist_throws() {
        Long b = registerUser("13910000111", "乙").getUserId();

        BusinessException e = assertThrows(BusinessException.class,
                () -> friendService.acceptRequest(b, 999999L));
        assertEquals(ErrorCode.FRIEND_REQUEST_NOT_FOUND.getCode(), e.getCode());
    }

    @Test
    void acceptRequest_notTheRecipient_throws() {
        Long a = registerUser("13910000112", "甲").getUserId();
        Long b = registerUser("13910000113", "乙").getUserId();
        Long c = registerUser("13910000114", "丙").getUserId();

        friendService.sendRequest(a, b);
        Long requestId = row(a, b).getId();

        BusinessException e = assertThrows(BusinessException.class,
                () -> friendService.acceptRequest(c, requestId));
        assertEquals(ErrorCode.FRIEND_REQUEST_NOT_FOUND.getCode(), e.getCode());
    }

    @Test
    void rejectRequest_removesPendingRow() {
        Long a = registerUser("13910000115", "甲").getUserId();
        Long b = registerUser("13910000116", "乙").getUserId();

        friendService.sendRequest(a, b);
        Long requestId = row(a, b).getId();
        friendService.rejectRequest(b, requestId);

        assertEquals(0, count(a, b));
    }

    @Test
    void friendList_returnsAcceptedOnly() {
        Long a = registerUser("13910000117", "甲").getUserId();
        Long b = registerUser("13910000118", "乙").getUserId();
        Long c = registerUser("13910000119", "丙").getUserId();

        makeFriends(a, b);
        friendService.sendRequest(a, c);

        List<FriendItemResponse> friends = friendService.friendList(a);
        assertEquals(1, friends.size());
        assertEquals(b, friends.get(0).getUserId());
    }

    @Test
    void incomingRequests_returnsPendingToMe() {
        Long a = registerUser("13910000120", "甲").getUserId();
        Long b = registerUser("13910000121", "乙").getUserId();

        friendService.sendRequest(a, b);

        List<FriendRequestResponse> requests = friendService.incomingRequests(b);
        assertEquals(1, requests.size());
        assertEquals(a, requests.get(0).getUserId());
    }

    @Test
    void search_excludesSelfAndFriends() {
        Long a = registerUser("13910000122", "跑者甲").getUserId();
        Long b = registerUser("13910000123", "跑者乙").getUserId();
        Long c = registerUser("13910000124", "跑者丙").getUserId();

        makeFriends(a, b);

        PageResponse<UserBriefResponse> result = friendService.search(a, "跑者", 1, 20);
        assertEquals(1, result.getTotal());
        assertEquals(c, result.getList().get(0).getUserId());
    }

    @Test
    void search_matchesByUniqueId() {
        Long a = registerUser("13910000125", "甲").getUserId();
        LoginResponse cResp = registerUser("13910000126", "丙");

        PageResponse<UserBriefResponse> result = friendService.search(a, cResp.getUniqueId(), 1, 20);
        assertEquals(1, result.getTotal());
        assertEquals(cResp.getUserId(), result.getList().get(0).getUserId());
    }

    @Test
    void search_matchesByPhone() {
        Long a = registerUser("13910000127", "甲").getUserId();
        LoginResponse cResp = registerUser("13910000128", "丙");

        PageResponse<UserBriefResponse> result = friendService.search(a, cResp.getPhone(), 1, 20);
        assertEquals(1, result.getTotal());
        assertEquals(cResp.getUserId(), result.getList().get(0).getUserId());
    }

    @Test
    void deleteFriend_removesBothDirections() {
        Long a = registerUser("13910000129", "甲").getUserId();
        Long b = registerUser("13910000130", "乙").getUserId();

        makeFriends(a, b);
        friendService.deleteFriend(a, b);

        assertEquals(0, count(a, b));
        assertEquals(0, count(b, a));
    }

    @Test
    void deleteFriend_notFriend_throws() {
        Long a = registerUser("13910000131", "甲").getUserId();
        Long b = registerUser("13910000132", "乙").getUserId();

        BusinessException e = assertThrows(BusinessException.class,
                () -> friendService.deleteFriend(a, b));
        assertEquals(ErrorCode.FRIEND_NOT_FOUND.getCode(), e.getCode());
    }

    @Test
    void sendRequest_success_publishesFriendRequestEvent() {
        Long a = registerUser("13910000133", "甲").getUserId();
        Long b = registerUser("13910000134", "乙").getUserId();

        friendService.sendRequest(a, b);

        List<FriendRequestEvent> published = events.of(FriendRequestEvent.class);
        assertEquals(1, published.size());
        FriendRequestEvent event = published.get(0);
        assertEquals(b, event.getTargetUserId());
        assertEquals(a, event.getData().getFromUserId());
        assertEquals("甲", event.getData().getFromNickname());
    }

    @Test
    void acceptRequest_success_publishesFriendAcceptedEvent() {
        Long a = registerUser("13910000135", "甲").getUserId();
        Long b = registerUser("13910000136", "乙").getUserId();
        friendService.sendRequest(a, b);
        Long requestId = row(a, b).getId();

        friendService.acceptRequest(b, requestId);

        List<FriendAcceptedEvent> published = events.of(FriendAcceptedEvent.class);
        assertEquals(1, published.size());
        FriendAcceptedEvent event = published.get(0);
        assertEquals(a, event.getTargetUserId());
        assertEquals(b, event.getData().getFriendUserId());
    }

    @Test
    void deleteFriend_success_publishesFriendDeletedEvent() {
        Long a = registerUser("13910000137", "甲").getUserId();
        Long b = registerUser("13910000138", "乙").getUserId();
        makeFriends(a, b);

        friendService.deleteFriend(a, b);

        List<FriendDeletedEvent> published = events.of(FriendDeletedEvent.class);
        assertEquals(1, published.size());
        FriendDeletedEvent event = published.get(0);
        assertEquals(b, event.getTargetUserId());
        assertEquals(a, event.getData().getFriendUserId());
    }

    @TestConfiguration
    static class FriendEventCaptureConfig {
        @Bean
        FriendEventCapture friendEventCapture() {
            return new FriendEventCapture();
        }
    }

    static class FriendEventCapture {
        private final List<Object> captured = new ArrayList<>();

        @EventListener
        void onFriendRequest(FriendRequestEvent event) {
            captured.add(event);
        }

        @EventListener
        void onFriendAccepted(FriendAcceptedEvent event) {
            captured.add(event);
        }

        @EventListener
        void onFriendDeleted(FriendDeletedEvent event) {
            captured.add(event);
        }

        void clear() {
            captured.clear();
        }

        <T> List<T> of(Class<T> type) {
            return captured.stream()
                    .filter(type::isInstance)
                    .map(type::cast)
                    .toList();
        }
    }
}
