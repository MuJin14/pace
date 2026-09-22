package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.FenceCreateRequest;
import com.campusrun.server.dto.request.FenceUpdateRequest;
import com.campusrun.server.dto.response.FenceResponse;
import com.campusrun.server.service.FenceService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/admin/fences")
public class FenceController {

    private final FenceService fenceService;

    public FenceController(FenceService fenceService) {
        this.fenceService = fenceService;
    }

    @GetMapping
    @PreAuthorize("hasRole('ADMIN')")
    public Result<List<FenceResponse>> list() {
        return Result.success(fenceService.list());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<FenceResponse> get(@PathVariable Long id) {
        return Result.success(fenceService.get(id));
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public Result<FenceResponse> create(@Valid @RequestBody FenceCreateRequest request) {
        return Result.success(fenceService.create(request));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<FenceResponse> update(@PathVariable Long id, @Valid @RequestBody FenceUpdateRequest request) {
        return Result.success(fenceService.update(id, request));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<Void> disable(@PathVariable Long id) {
        fenceService.disable(id);
        return Result.success();
    }
}
