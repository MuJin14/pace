package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.UserService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

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
}
