package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.dto.response.MyRankResponse;

import java.time.LocalDateTime;

public interface LeaderboardService {

    /**
     * 将一次运动记录累加到日榜、周榜、月榜。
     *
     * @param userId         用户 ID
     * @param distanceMeters 距离（米）
     * @param startTime      运动开始时间（用于确定所属周期）
     * @param activityType   运动类型（1=跑步，2=骑行）
     */
    void recordActivity(Long userId, int distanceMeters, LocalDateTime startTime, int activityType);

    /**
     * 分页查询排行榜。
     *
     * @param scope  榜单维度（daily/weekly/monthly/rolling30d）
     * @param period 榜单周期（如 yyyy-MM-dd、yyyy-MM），可为 null 表示当前周期
     * @param type   运动类型（1=跑步，2=骑行）
     * @param page   页码（从 1 起）
     * @param size   每页条数
     * @return 榜单分页列表（含排名）
     * @throws BusinessException 维度、类型或周期格式不合法
     */
    PageResponse<LeaderboardEntryResponse> getBoard(String scope, String period, Integer type, long page, long size);

    /**
     * 查询当前用户在指定榜单的名次。
     *
     * @param scope  榜单维度
     * @param period 榜单周期，可为 null 表示当前周期
     * @param type   运动类型
     * @param userId 用户 ID
     * @return 名次、距离与总人数
     * @throws BusinessException 维度、类型或周期格式不合法
     */
    MyRankResponse getMyRank(String scope, String period, Integer type, Long userId);

    /**
     * 重算滚动 30 天榜（定时任务调用）。
     */
    void rebuildRolling30d();

    /**
     * 清理过期榜单数据（定时任务调用）。
     */
    void cleanupExpired();
}
