package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.FriendRequestResponse;
import com.campusrun.server.dto.response.UserBriefResponse;

import java.util.List;

public interface FriendService {

    PageResponse<UserBriefResponse> search(Long userId, String keyword, long page, long size);

    void sendRequest(Long userId, Long targetUserId);

    void acceptRequest(Long userId, Long requestId);

    void rejectRequest(Long userId, Long requestId);

    List<FriendRequestResponse> incomingRequests(Long userId);

    List<FriendItemResponse> friendList(Long userId);

    void deleteFriend(Long userId, Long friendId);
}
