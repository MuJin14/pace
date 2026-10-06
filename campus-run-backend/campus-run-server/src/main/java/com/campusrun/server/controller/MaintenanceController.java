package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.response.DistanceRepairResult;
import com.campusrun.server.service.DistanceRepairService;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 数据维护接口（仅 ADMIN）。
 *
 * <p>为什么做成接口而不是一次性 SQL 脚本：修复逻辑要用到**新版本的距离算法**
 * （`GpsUtil.totalDistanceMetersFiltered`）。SQL 里重写一遍等于维护两套算法，
 * 一旦两边漂移就会重演「成绩用过滤值、判定用原始值」那类事故。
 * 走接口则复用同一份代码，与线上计算口径天然一致。
 */
@RestController
@RequestMapping("/api/v1/admin/maintenance")
public class MaintenanceController {

    private final DistanceRepairService distanceRepairService;

    public MaintenanceController(DistanceRepairService distanceRepairService) {
        this.distanceRepairService = distanceRepairService;
    }

    /**
     * 修复历史「距离为 0」的运动记录，并重算由距离派生的全部聚合值。
     *
     * <p>⚠️ **先用 `dryRun=true` 预演**，确认 `fixedActivities` 符合预期再正式执行。
     *
     * <p>幂等：可以重复执行，第二次 `fixedActivities` 会是 0，聚合值不变。
     *
     * <pre>
     * POST /api/v1/admin/maintenance/repair-distance?dryRun=true
     * </pre>
     */
    @PostMapping("/repair-distance")
    @PreAuthorize("hasRole('ADMIN')")
    public Result<DistanceRepairResult> repairDistance(
            @RequestParam(name = "dryRun", defaultValue = "true") boolean dryRun) {
        return Result.success(distanceRepairService.repairZeroDistanceActivities(dryRun));
    }
}
