package com.campusrun.server.service;

import com.campusrun.server.dto.request.GoalCreateRequest;
import com.campusrun.server.dto.response.GoalResponse;

import java.time.LocalDateTime;
import java.util.List;

public interface GoalService {

    /**
     * 创建运动目标（同周期同类型仅允许一个进行中的目标）。
     *
     * @param userId  用户 ID
     * @param request 创建请求（周期类型、目标距离、起止日期）
     * @return 新建目标
     * @throws BusinessException 周期类型不合法、日期非法或同周期目标已存在
     */
    GoalResponse create(Long userId, GoalCreateRequest request);

    /**
     * 查询用户的全部目标，按创建时间倒序。
     *
     * @param userId 用户 ID
     * @return 目标列表
     */
    List<GoalResponse> list(Long userId);

    /**
     * 查询单个目标。
     *
     * @param userId 用户 ID
     * @param goalId 目标 ID
     * @return 目标详情
     * @throws BusinessException 目标不存在
     */
    GoalResponse get(Long userId, Long goalId);

    /**
     * 取消进行中的目标。
     *
     * @param userId 用户 ID
     * @param goalId 目标 ID
     * @throws BusinessException 目标不存在或不可操作
     */
    void cancel(Long userId, Long goalId);

    /**
     * 按运动开始时间匹配各进行中目标的所属周期，命中则累加进度。
     *
     * @param userId         用户 ID
     * @param distanceMeters 距离（米）
     * @param startTime      运动开始时间
     */
    void addProgress(Long userId, int distanceMeters, LocalDateTime startTime);

    /**
     * 将已过期目标置为完成或过期（定时任务调用）。
     */
    void expireOutdated();
}
