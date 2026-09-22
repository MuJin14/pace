package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.AcceptFriendRequest;
import com.campusrun.server.dto.request.RejectFriendRequest;
import com.campusrun.server.dto.request.SendFriendRequest;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.FriendRequestResponse;
import com.campusrun.server.dto.response.UserBriefResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.FriendService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/friend")
public class FriendController {

    private final FriendService friendService;

    public FriendController(FriendService friendService) {
        this.friendService = friendService;
    }

    @GetMapping("/search")
    public Result<PageResponse<UserBriefResponse>> search(
            @RequestParam String keyword,
            @RequestParam(defaultValue = "1") long page,
            @RequestParam(defaultValue = "20") long size) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(friendService.search(userId, keyword, page, size));
    }

    @PostMapping("/request")
    public Result<Void> sendRequest(@Valid @RequestBody SendFriendRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        friendService.sendRequest(userId, request.getTargetUserId());
        return Result.success();
    }

    @PostMapping("/accept")
    public Result<Void> acceptRequest(@Valid @RequestBody AcceptFriendRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        friendService.acceptRequest(userId, request.getRequestId());
        return Result.success();
    }

    @PostMapping("/reject")
    public Result<Void> rejectRequest(@Valid @RequestBody RejectFriendRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        friendService.rejectRequest(userId, request.getRequestId());
        return Result.success();
    }

    @GetMapping("/requests")
    public Result<List<FriendRequestResponse>> incomingRequests() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(friendService.incomingRequests(userId));
    }

    @GetMapping("/list")
    public Result<List<FriendItemResponse>> friendList() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(friendService.friendList(userId));
    }

    @DeleteMapping("/{friendId}")
    public Result<Void> deleteFriend(@PathVariable Long friendId) {
        Long userId = SecurityUtils.getCurrentUserId();
        friendService.deleteFriend(userId, friendId);
        return Result.success();
    }
}
