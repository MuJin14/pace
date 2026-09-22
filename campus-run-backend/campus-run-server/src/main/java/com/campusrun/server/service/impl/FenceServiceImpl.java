package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.cache.FenceCache;
import com.campusrun.server.dto.request.FenceCreateRequest;
import com.campusrun.server.dto.request.FenceUpdateRequest;
import com.campusrun.server.dto.response.FenceResponse;
import com.campusrun.server.entity.CampusFence;
import com.campusrun.server.mapper.CampusFenceMapper;
import com.campusrun.server.model.FenceMatchResult;
import com.campusrun.server.model.TrackPoint;
import com.campusrun.server.service.FenceService;
import com.campusrun.server.util.GpsUtil;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

@Service
public class FenceServiceImpl implements FenceService {

    private static final BigDecimal DEFAULT_OUTSIDE_RATIO = new BigDecimal("0.3000");

    private final CampusFenceMapper fenceMapper;
    private final FenceCache fenceCache;

    public FenceServiceImpl(CampusFenceMapper fenceMapper, FenceCache fenceCache) {
        this.fenceMapper = fenceMapper;
        this.fenceCache = fenceCache;
    }

    @Override
    public List<FenceResponse> list() {
        return fenceMapper.selectList(null).stream().map(this::toResponse).toList();
    }

    @Override
    public FenceResponse get(Long id) {
        return toResponse(requireFence(id));
    }

    @Override
    public FenceResponse create(FenceCreateRequest request) {
        CampusFence fence = new CampusFence();
        fence.setName(request.getName());
        fence.setCenterLat(request.getCenterLat());
        fence.setCenterLng(request.getCenterLng());
        fence.setRadiusMeters(request.getRadiusMeters());
        fence.setAllowedOutsideRatio(request.getAllowedOutsideRatio() == null
                ? DEFAULT_OUTSIDE_RATIO : request.getAllowedOutsideRatio());
        fence.setEnabled(1);
        fenceMapper.insert(fence);
        fenceCache.invalidate();
        return toResponse(fence);
    }

    @Override
    public FenceResponse update(Long id, FenceUpdateRequest request) {
        CampusFence fence = requireFence(id);
        fence.setName(request.getName());
        fence.setCenterLat(request.getCenterLat());
        fence.setCenterLng(request.getCenterLng());
        fence.setRadiusMeters(request.getRadiusMeters());
        fence.setAllowedOutsideRatio(request.getAllowedOutsideRatio() == null
                ? DEFAULT_OUTSIDE_RATIO : request.getAllowedOutsideRatio());
        fenceMapper.updateById(fence);
        fenceCache.invalidate();
        return toResponse(fence);
    }

    @Override
    public void disable(Long id) {
        CampusFence fence = requireFence(id);
        fence.setEnabled(0);
        fenceMapper.updateById(fence);
        fenceCache.invalidate();
    }

    @Override
    public FenceMatchResult evaluate(List<TrackPoint> track) {
        List<CampusFence> fences = fenceCache.getEnabledFences();
        if (fences.isEmpty()) {
            return FenceMatchResult.valid(null, null);
        }

        int total = track.size();
        CampusFence best = null;
        int bestInside = -1;
        for (CampusFence fence : fences) {
            int inside = 0;
            for (TrackPoint point : track) {
                double distance = GpsUtil.distanceMeters(
                        point.getLatitude(), point.getLongitude(),
                        fence.getCenterLat().doubleValue(), fence.getCenterLng().doubleValue());
                if (distance <= fence.getRadiusMeters().doubleValue()) {
                    inside++;
                }
            }
            if (inside > bestInside) {
                bestInside = inside;
                best = fence;
            }
        }

        double maxInsideRatio = (double) bestInside / total;
        BigDecimal outsideRatio = round(1.0 - maxInsideRatio);
        double allowedInside = 1.0 - best.getAllowedOutsideRatio().doubleValue();

        if (maxInsideRatio >= allowedInside) {
            return FenceMatchResult.valid(best.getId(), outsideRatio);
        }
        return FenceMatchResult.invalid(outsideRatio);
    }

    private CampusFence requireFence(Long id) {
        CampusFence fence = fenceMapper.selectById(id);
        if (fence == null) {
            throw new BusinessException(ErrorCode.FENCE_NOT_FOUND);
        }
        return fence;
    }

    private FenceResponse toResponse(CampusFence fence) {
        FenceResponse response = new FenceResponse();
        response.setId(fence.getId());
        response.setName(fence.getName());
        response.setCenterLat(fence.getCenterLat());
        response.setCenterLng(fence.getCenterLng());
        response.setRadiusMeters(fence.getRadiusMeters());
        response.setAllowedOutsideRatio(fence.getAllowedOutsideRatio());
        response.setEnabled(fence.getEnabled());
        response.setCreatedAt(fence.getCreatedAt());
        response.setUpdatedAt(fence.getUpdatedAt());
        return response;
    }

    private BigDecimal round(double value) {
        return BigDecimal.valueOf(value).setScale(4, RoundingMode.HALF_UP);
    }
}
