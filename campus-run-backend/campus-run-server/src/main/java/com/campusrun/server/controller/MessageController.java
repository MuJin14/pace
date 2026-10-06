package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.MessageService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/message")
public class MessageController {

    private final MessageService messageService;

    public MessageController(MessageService messageService) {
        this.messageService = messageService;
    }

    @GetMapping("/history")
    public Result<PageResponse<ChatMessageResponse>> history(
            @RequestParam Long friendId,
            @RequestParam(required = false) Long beforeId,
            @RequestParam(defaultValue = "20") long size) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(messageService.history(userId, friendId, beforeId, size));
    }

    /**
     * 显式标记消息已读（拉取历史已自动标记，本接口用于精确补标）。
     * 参数为重复 query 参数：/api/v1/message/read?messageIds=1&messageIds=2
     */

    /**
     * 当前用户的未读消息数（按发送方分组）。
     *
     * <p>客户端在**登录后**与**回到前台**时调用。存在的理由：
     * 未读红点原本只靠 WebSocket 实时累加，是纯内存态 ——
     * 设备离线（或被顶下线）期间收到的消息，登录后完全没有红点提示，
     * 用户不知道有人给自己发过消息。
     */
    @GetMapping("/unread")
    public Result<java.util.Map<Long, Integer>> unread() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(messageService.unreadCounts(userId));
    }

    @PostMapping("/read")
    public Result<Integer> markRead(@RequestParam(required = false) List<Long> messageIds) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(messageService.markRead(userId, messageIds));
    }
}
