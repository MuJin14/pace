package com.campusrun.server.controller;

import com.campusrun.common.result.PageResponse;
import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.ActivityCreateRequest;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.ActivityDetailResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.ActivityService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/activity")
public class ActivityController {

    private final ActivityService activityService;

    public ActivityController(ActivityService activityService) {
        this.activityService = activityService;
    }

    @PostMapping
    public Result<ActivityCreateResponse> create(@Valid @RequestBody ActivityCreateRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(activityService.create(userId, request));
    }

    @GetMapping
    public Result<PageResponse<ActivitySummaryResponse>> page(
            @RequestParam(required = false) Integer type,
            @RequestParam(defaultValue = "1") long page,
            @RequestParam(defaultValue = "20") long size) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(activityService.page(userId, type, page, size));
    }

    @GetMapping("/{id}")
    public Result<ActivityDetailResponse> detail(@PathVariable Long id) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(activityService.getDetail(userId, id));
    }
}
