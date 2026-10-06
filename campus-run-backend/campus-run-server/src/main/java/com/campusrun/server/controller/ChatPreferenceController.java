package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.ChatPreferenceService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 聊天会话偏好（免打扰）。
 *
 * <p>免打扰是**单向、按会话**的：A 静音 B 的消息提醒，不影响 B 是否收到 A 的提醒。
 * 这是主流 IM 的语义；双向静音会变成「对方能单方面让你收不到消息」，容易被滥用。
 *
 * <p>免打扰只拦离线推送通知，**不拦消息本身** —— 消息照常送达、照常入库。
 */
@RestController
@RequestMapping("/api/v1/chat/preference")
public class ChatPreferenceController {

    private final ChatPreferenceService chatPreferenceService;

    public ChatPreferenceController(ChatPreferenceService chatPreferenceService) {
        this.chatPreferenceService = chatPreferenceService;
    }

    /**
     * 查询自己所有「免打扰」的会话对方 id。
     *
     * <p>返回一份静音名单，前端据此决定是否震动/弹通知。
     */
    @GetMapping("/muted")
    public Result<List<Long>> mutedFriendIds() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(chatPreferenceService.mutedFriendIds(userId));
    }

    /**
     * 设置或取消对某个会话的免打扰（幂等）。
     *
     * @param friendId 会话对方用户 id
     * @param muted    true=免打扰，false=取消
     */
    @PutMapping
    public Result<Void> setMuted(@RequestParam Long friendId,
                                 @RequestParam boolean muted) {
        Long userId = SecurityUtils.getCurrentUserId();
        chatPreferenceService.setMuted(userId, friendId, muted);
        return Result.success();
    }
}
