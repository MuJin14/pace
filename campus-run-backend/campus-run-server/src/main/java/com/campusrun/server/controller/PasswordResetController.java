package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.PasswordResetRequestItem;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.AdminUserService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 密码重置申请的**用户侧**入口。
 *
 * <p>与 {@code AdminController} 分开的原因：这里的提交接口必须**允许未登录访问**
 * （用户就是登不上才来申请的）。放在 `/api/v1/**` 下，
 * 需要在安全配置里对这一个路径放行 —— 而不是把整个 `/api/v1/admin/**` 放开。
 *
 * <p>提交接口不做「手机号是否注册」的区分（见 Service 注释）：
 * 否则它会变成一个手机号枚举器。
 */
@RestController
@RequestMapping("/api/v1/password-reset-requests")
public class PasswordResetController {

    private final AdminUserService adminUserService;

    public PasswordResetController(AdminUserService adminUserService) {
        this.adminUserService = adminUserService;
    }

    /**
     * 提交重置申请（**无需登录**）。
     *
     * <p>无论手机号是否注册都返回成功，避免账号枚举。
     */
    @PostMapping
    public Result<Void> submit(@RequestParam String phone,
                               @RequestParam(required = false) String note) {
        adminUserService.createResetRequest(phone, note);
        return Result.success(null);
    }

    /** 查看自己最近一次申请的处理状态（需登录）。 */
    @GetMapping("/mine")
    public Result<PasswordResetRequestItem> mine() {
        return Result.success(adminUserService.myLatestRequest(SecurityUtils.getCurrentUserId()));
    }
}
