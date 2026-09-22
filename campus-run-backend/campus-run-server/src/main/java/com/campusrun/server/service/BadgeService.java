package com.campusrun.server.service;

import com.campusrun.server.dto.response.BadgeResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;

import java.time.LocalDateTime;
import java.util.List;

public interface BadgeService {

    /**
     * 查询全部启用勋章，并标注当前用户是否已获得及获得时间。
     *
     * @param userId 用户 ID
     * @return 勋章列表（含获得状态）
     */
    List<BadgeResponse> listAll(Long userId);

    /**
     * 查询当前用户已获得的勋章，按获得时间倒序。
     *
     * @param userId 用户 ID
     * @return 已获勋章列表
     */
    List<UserBadgeResponse> listMine(Long userId);

    /**
     * 根据一次运动更新用户统计并判发符合条件的勋章。
     *
     * @param userId         用户 ID
     * @param distanceMeters 距离（米）
     * @param startTime      运动开始时间
     */
    void evaluateOnActivity(Long userId, int distanceMeters, LocalDateTime startTime);

    /**
     * 重置中断的连续运动天数（定时任务调用）。
     */
    void resetStreaks();

    /**
     * 结算已结束的周目标并判发相关勋章（定时任务调用）。
     */
    void checkWeeklyGoals();
}
