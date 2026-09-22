package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ActivityCreateRequest;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.ActivityDetailResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;

public interface ActivityService {

    ActivityCreateResponse create(Long userId, ActivityCreateRequest request);

    PageResponse<ActivitySummaryResponse> page(Long userId, Integer type, long page, long size);

    ActivityDetailResponse getDetail(Long userId, Long activityId);
}
