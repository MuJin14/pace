package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.AdminUserItem;
import com.campusrun.server.dto.response.PasswordResetRequestItem;
import com.campusrun.server.dto.response.PasswordResetResult;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.AdminUserService;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 管理后台：用户查询与密码协助重置。
 *
 * <p>整个类的入口都在 `/api/v1/admin/**` 下，且每个方法都标注
 * `@PreAuthorize("hasRole('ADMIN')")`。**不要**把这里的任何方法挪到无需鉴权的路径下 ——
 * 重置密码的权限等于接管账号。
 */
@RestController
@RequestMapping("/api/v1/admin")
public class AdminController {

    private final AdminUserService adminUserService;

    public AdminController(AdminUserService adminUserService) {
        this.adminUserService = adminUserService;
    }

    /** 分页查询用户，可按手机号 / 昵称 / 专属 ID 模糊搜索。 */
    @GetMapping("/users")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<PageResponse<AdminUserItem>> listUsers(
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "1") long page,
            @RequestParam(defaultValue = "20") long size) {
        return Result.success(adminUserService.listUsers(keyword, page, size));
    }

    /**
     * 直接为指定用户重置密码（管理员主动发起，不需要对方先申请）。
     *
     * <p>返回的临时密码**只出现这一次**：服务端只存 BCrypt 哈希，无法再读回。
     */
    @PostMapping("/users/{userId}/reset-password")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<PasswordResetResult> resetPassword(@PathVariable Long userId) {
        return Result.success(adminUserService.resetPassword(SecurityUtils.getCurrentUserId(), userId));
    }

    /** 查看密码重置申请列表（默认全部；`status=0` 只看待处理）。 */
    @GetMapping("/password-reset-requests")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<List<PasswordResetRequestItem>> listRequests(
            @RequestParam(required = false) Integer status) {
        return Result.success(adminUserService.listRequests(status));
    }

    /** 处理申请：重置密码并标记为已重置。 */
    @PostMapping("/password-reset-requests/{id}/resolve")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<PasswordResetResult> resolve(@PathVariable Long id) {
        return Result.success(
                adminUserService.handleRequest(SecurityUtils.getCurrentUserId(), id));
    }

    /** 拒绝申请（例如申请人无法证明账号归属）。 */
    @PostMapping("/password-reset-requests/{id}/reject")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<Void> reject(@PathVariable Long id) {
        adminUserService.rejectRequest(SecurityUtils.getCurrentUserId(), id);
        return Result.success(null);
    }
}
