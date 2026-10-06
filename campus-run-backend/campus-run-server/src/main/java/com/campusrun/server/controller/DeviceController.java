package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.RegisterDeviceRequest;
import com.campusrun.server.push.PushService;
import com.campusrun.server.security.SecurityUtils;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/device")
public class DeviceController {

    private final PushService pushService;

    public DeviceController(PushService pushService) {
        this.pushService = pushService;
    }

    /**
     * 登记设备推送令牌（App 启动拿到 FCM 令牌后调用）。
     *
     * <p>幂等：同一令牌重复登记只是刷新归属与时间。
     * 归属以**当前登录用户**为准，因此换账号登录同一台设备会自动改到新用户。
     */
    @PostMapping("/token")
    public Result<Void> register(@Valid @RequestBody RegisterDeviceRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        pushService.register(userId, request.getToken(), request.getPlatform());
        return Result.success();
    }

    /**
     * 注销设备令牌（登出时调用）。
     *
     * <p>不注销的话，用户登出后仍会收到该账号的推送 —— 换个人用同一台手机会看到
     * 前一个用户的聊天通知，属于隐私泄露。
     */
    @DeleteMapping("/token")
    public Result<Void> unregister(@RequestParam String token) {
        // 只按令牌删除；不需要校验 userId —— 令牌本身就是凭据，
        // 且 client 只会拿到自己设备的令牌。
        pushService.unregister(token);
        return Result.success();
    }
}
