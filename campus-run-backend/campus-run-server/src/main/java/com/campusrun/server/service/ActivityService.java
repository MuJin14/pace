package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ActivityCreateRequest;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.ActivityDetailResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;

public interface ActivityService {

    /**
     * 创建运动记录：计算轨迹距离并落库，专属模式先做围栏校验，有效记录再联动排行榜、目标与勋章。
     *
     * @param userId  发起用户 ID
     * @param request 创建请求（运动类型、起止时间、轨迹点等）
     * @return 创建结果（含距离、平均配速、是否作废等）
     * @throws BusinessException 参数不合法、轨迹距离为 0、轨迹点数量不足或超上限
     */
    ActivityCreateResponse create(Long userId, ActivityCreateRequest request);

    /**
     * 分页查询当前用户的运动记录，按开始时间倒序。
     *
     * @param userId 当前用户 ID
     * @param type   运动类型（1=跑步，2=骑行），可为 null 表示全部
     * @param page   页码（从 1 起）
     * @param size   每页条数
     * @return 运动记录分页列表
     */
    PageResponse<ActivitySummaryResponse> page(Long userId, Integer type, long page, long size);

    /**
     * 查询运动记录详情（含轨迹）。
     *
     * @param userId     当前用户 ID
     * @param activityId 运动记录 ID
     * @return 运动记录详情
     * @throws BusinessException 记录不存在或无权访问
     */
    ActivityDetailResponse getDetail(Long userId, Long activityId);
}
