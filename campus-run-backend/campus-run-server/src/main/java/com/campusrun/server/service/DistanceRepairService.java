package com.campusrun.server.service;

import com.campusrun.server.dto.response.DistanceRepairResult;

/**
 * 「运动记录距离为 0」的历史数据修复。
 *
 * <p><b>为什么需要它</b>：距离过滤算法在 2026-10 修复（逐段阈值 → 滑窗方向一致性）后，
 * **只对新的运动生效**。库里已经存下的记录 `distance_meters` 仍是当初算错的 0 ——
 * 用户看到旧记录还是 0，会认为「根本没修好」。
 * 轨迹 JSON 还在，所以可以用新算法重算。
 *
 * <p><b>为什么不能只改 activity 表</b>：距离被三处聚合吃掉了
 * （`user_stats` 累计里程/次数、`leaderboard_stats` 日/周/月/rolling30d、
 * `user_goal` 目标进度），只改原表会让「记录对了但排行榜还是错的」。
 * 所以本服务在修完记录后，把这三种聚合**按 activity 全量重算**。
 *
 * <p><b>幂等性</b>：全部采用「先删后重算」，结果只由 activity 决定，
 * 因此可以安全地重复执行（第二次执行时 `fixedActivities = 0`，聚合值不变）。
 */
public interface DistanceRepairService {

    /**
     * 执行修复。
     *
     * @param dryRun true = 只统计不写库（先用它评估影响面，确认无误再正式执行）
     */
    DistanceRepairResult repairZeroDistanceActivities(boolean dryRun);
}
