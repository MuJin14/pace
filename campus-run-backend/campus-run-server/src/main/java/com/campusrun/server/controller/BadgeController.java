package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.BadgeResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.BadgeService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/badges")
public class BadgeController {

    private final BadgeService badgeService;

    public BadgeController(BadgeService badgeService) {
        this.badgeService = badgeService;
    }

    @GetMapping
    public Result<List<BadgeResponse>> list() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(badgeService.listAll(userId));
    }

    @GetMapping("/mine")
    public Result<List<UserBadgeResponse>> mine() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(badgeService.listMine(userId));
    }
}
