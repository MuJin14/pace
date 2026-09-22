package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.MessageService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

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
}
