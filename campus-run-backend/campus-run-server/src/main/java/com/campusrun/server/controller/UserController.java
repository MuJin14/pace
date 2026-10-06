package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.ChangePasswordRequest;
import com.campusrun.server.dto.request.UpdateProfileRequest;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.dto.response.UserProfileResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.UserService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/user")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/me")
    public Result<UserInfoResponse> me() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(userService.getCurrentUser(userId));
    }

    /**
     * 查看任意用户的公开主页（含与当前用户的关系）。
     * 不返回手机号；手机号只在 {@code /me} 对自己可见。
     */
    @GetMapping("/{userId}/profile")
    public Result<UserProfileResponse> profile(@PathVariable Long userId) {
        Long me = SecurityUtils.getCurrentUserId();
        return Result.success(userService.getProfile(me, userId));
    }

    /** 更新自己的资料（昵称 / 头像 / 性别 / 年龄及其可见性）。字段为空表示不修改该字段。 */
    @PutMapping("/me")
    public Result<UserInfoResponse> updateProfile(@Valid @RequestBody UpdateProfileRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(userService.updateProfile(userId, request));
    }

    /**
     * 修改密码。需提供当前密码。
     *
     * <p>成功后**此前签发的所有 refresh token 立即失效**（服务端写入 token_invalid_before），
     * 也就是「改密即全端下线」。前端应清空本地令牌并回登录页。
     */
    @PutMapping("/password")
    public Result<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        userService.changePassword(userId, request);
        return Result.success();
    }

    /**
     * 看某人的运动记录（仅好友可见）。
     *
     * <p>权限判定放在 Service：不是好友返回 403，而不是返回空列表 ——
     * 空列表会让调用方分不清「没权限」和「对方没记录」。
     */
    @GetMapping("/{userId}/activities")
    public Result<PageResponse<ActivitySummaryResponse>> activities(
            @PathVariable Long userId,
            @RequestParam(required = false) Integer type,
            @RequestParam(defaultValue = "1") long page,
            @RequestParam(defaultValue = "10") long size) {
        Long me = SecurityUtils.getCurrentUserId();
        return Result.success(userService.listUserActivities(me, userId, type, page, size));
    }

    /** 看某人的勋章墙（仅好友可见）。 */
    @GetMapping("/{userId}/badges")
    public Result<List<UserBadgeResponse>> badges(@PathVariable Long userId) {
        Long me = SecurityUtils.getCurrentUserId();
        return Result.success(userService.listUserBadges(me, userId));
    }

    /**
     * 注销账号（合规要求的「删除权」）。删除不可恢复，前端必须二次确认。
     * 只允许注销自己：userId 取自当前登录态，不接受请求参数。
     */
    @DeleteMapping("/me")
    public Result<Void> deleteAccount() {
        Long userId = SecurityUtils.getCurrentUserId();
        userService.deleteAccount(userId);
        return Result.success();
    }
}
