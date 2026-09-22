package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.GoalCreateRequest;
import com.campusrun.server.dto.response.GoalResponse;
import com.campusrun.server.security.SecurityUtils;
import com.campusrun.server.service.GoalService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/goals")
public class GoalController {

    private final GoalService goalService;

    public GoalController(GoalService goalService) {
        this.goalService = goalService;
    }

    @PostMapping
    public Result<GoalResponse> create(@Valid @RequestBody GoalCreateRequest request) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(goalService.create(userId, request));
    }

    @GetMapping
    public Result<List<GoalResponse>> list() {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(goalService.list(userId));
    }

    @GetMapping("/{id}")
    public Result<GoalResponse> get(@PathVariable Long id) {
        Long userId = SecurityUtils.getCurrentUserId();
        return Result.success(goalService.get(userId, id));
    }

    @DeleteMapping("/{id}")
    public Result<Void> cancel(@PathVariable Long id) {
        Long userId = SecurityUtils.getCurrentUserId();
        goalService.cancel(userId, id);
        return Result.success();
    }
}
