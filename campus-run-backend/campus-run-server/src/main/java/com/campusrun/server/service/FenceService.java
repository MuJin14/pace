package com.campusrun.server.service;

import com.campusrun.server.dto.request.FenceCreateRequest;
import com.campusrun.server.dto.request.FenceUpdateRequest;
import com.campusrun.server.dto.response.FenceResponse;
import com.campusrun.server.model.FenceMatchResult;
import com.campusrun.server.model.TrackPoint;

import java.util.List;

public interface FenceService {

    /**
     * 查询全部围栏。
     *
     * @return 围栏列表
     */
    List<FenceResponse> list();

    /**
     * 查询单个围栏。
     *
     * @param id 围栏 ID
     * @return 围栏详情
     * @throws BusinessException 围栏不存在
     */
    FenceResponse get(Long id);

    /**
     * 新建围栏（默认启用），并失效缓存。
     *
     * @param request 创建请求（名称、圆心、半径、允许出圈比例）
     * @return 新建围栏
     */
    FenceResponse create(FenceCreateRequest request);

    /**
     * 更新围栏，并失效缓存。
     *
     * @param id      围栏 ID
     * @param request 更新请求
     * @return 更新后围栏
     * @throws BusinessException 围栏不存在
     */
    FenceResponse update(Long id, FenceUpdateRequest request);

    /**
     * 停用围栏，并失效缓存。
     *
     * @param id 围栏 ID
     * @throws BusinessException 围栏不存在
     */
    void disable(Long id);

    /**
     * 对轨迹做围栏匹配：返回覆盖比例最高的围栏，判断是否在允许出圈比例内。
     *
     * @param track 轨迹点列表
     * @return 匹配结果（命中围栏 ID、出圈比例、是否作废）
     */
    FenceMatchResult evaluate(List<TrackPoint> track);
}
