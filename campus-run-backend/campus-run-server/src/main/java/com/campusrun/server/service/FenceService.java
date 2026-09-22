package com.campusrun.server.service;

import com.campusrun.server.dto.request.FenceCreateRequest;
import com.campusrun.server.dto.request.FenceUpdateRequest;
import com.campusrun.server.dto.response.FenceResponse;
import com.campusrun.server.model.FenceMatchResult;
import com.campusrun.server.model.TrackPoint;

import java.util.List;

public interface FenceService {

    List<FenceResponse> list();

    FenceResponse get(Long id);

    FenceResponse create(FenceCreateRequest request);

    FenceResponse update(Long id, FenceUpdateRequest request);

    void disable(Long id);

    FenceMatchResult evaluate(List<TrackPoint> track);
}
