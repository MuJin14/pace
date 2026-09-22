package com.campusrun.server.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.ActivityCreateRequest;
import com.campusrun.server.dto.request.TrackPointRequest;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.ActivityDetailResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.entity.Activity;
import com.campusrun.server.mapper.ActivityMapper;
import com.campusrun.server.model.FenceMatchResult;
import com.campusrun.server.model.TrackPoint;
import com.campusrun.server.service.ActivityService;
import com.campusrun.server.service.BadgeService;
import com.campusrun.server.service.FenceService;
import com.campusrun.server.service.GoalService;
import com.campusrun.server.service.LeaderboardService;
import com.campusrun.server.util.GpsUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

@Service
public class ActivityServiceImpl implements ActivityService {

    private static final Logger log = LoggerFactory.getLogger(ActivityServiceImpl.class);
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final int MAX_RUNNING_POINTS = 5000;
    private static final int MAX_CYCLING_POINTS = 15000;

    private final ActivityMapper activityMapper;
    private final ObjectMapper objectMapper;
    private final LeaderboardService leaderboardService;
    private final FenceService fenceService;
    private final GoalService goalService;
    private final BadgeService badgeService;

    public ActivityServiceImpl(ActivityMapper activityMapper, ObjectMapper objectMapper,
                               LeaderboardService leaderboardService, FenceService fenceService,
                               GoalService goalService, BadgeService badgeService) {
        this.activityMapper = activityMapper;
        this.objectMapper = objectMapper;
        this.leaderboardService = leaderboardService;
        this.fenceService = fenceService;
        this.goalService = goalService;
        this.badgeService = badgeService;
    }

    @Override
    @Transactional
    public ActivityCreateResponse create(Long userId, ActivityCreateRequest request) {
        validate(request);

        List<TrackPoint> track = toTrackPoints(request.getTrack());
        double distance = GpsUtil.totalDistanceMeters(track);
        if (distance <= 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "轨迹距离为 0");
        }

        long durationSeconds = (request.getEndTime() - request.getStartTime()) / 1000;
        double avgSpeedKmh = (distance / 1000.0) / (durationSeconds / 3600.0);

        Activity activity = new Activity();
        activity.setUserId(userId);
        activity.setType(request.getType());
        activity.setMode(request.getMode() == null ? 1 : request.getMode());
        activity.setDistanceMeters((int) Math.round(distance));
        activity.setDurationSeconds((int) durationSeconds);
        activity.setAvgSpeed(BigDecimal.valueOf(avgSpeedKmh).setScale(2, RoundingMode.HALF_UP));
        activity.setCalories(request.getCalories() == null
                ? null
                : BigDecimal.valueOf(request.getCalories()).setScale(2, RoundingMode.HALF_UP));
        activity.setStartTime(toLocalDateTime(request.getStartTime()));
        activity.setEndTime(toLocalDateTime(request.getEndTime()));

        TrackPoint first = track.get(0);
        TrackPoint last = track.get(track.size() - 1);
        activity.setStartLat(BigDecimal.valueOf(first.getLatitude()));
        activity.setStartLng(BigDecimal.valueOf(first.getLongitude()));
        activity.setEndLat(BigDecimal.valueOf(last.getLatitude()));
        activity.setEndLng(BigDecimal.valueOf(last.getLongitude()));

        activity.setTrackJson(serializeTrack(track));

        if (isExclusiveMode(activity.getMode())) {
            FenceMatchResult match = fenceService.evaluate(track);
            activity.setInvalid(match.invalid() ? 1 : 0);
            activity.setFenceId(match.fenceId());
            activity.setOutsideRatio(match.outsideRatio());
        } else {
            activity.setInvalid(0);
        }

        activityMapper.insert(activity);

        if (activity.getInvalid() == null || activity.getInvalid() == 0) {
            leaderboardService.recordActivity(userId, activity.getDistanceMeters(), activity.getStartTime(), activity.getType());
            goalService.addProgress(userId, activity.getDistanceMeters(), activity.getStartTime());
            try {
                badgeService.evaluateOnActivity(userId, activity.getDistanceMeters(), activity.getStartTime());
            } catch (Exception e) {
                log.error("勋章判发失败，userId={}", userId, e);
            }
        }

        return buildCreateResponse(activity, (int) durationSeconds);
    }

    @Override
    public PageResponse<ActivitySummaryResponse> page(Long userId, Integer type, long page, long size) {
        long safePage = Math.max(1, page);
        long safeSize = Math.min(100, Math.max(1, size));

        LambdaQueryWrapper<Activity> wrapper = new LambdaQueryWrapper<Activity>()
                .eq(Activity::getUserId, userId)
                .eq(type != null, Activity::getType, type)
                .orderByDesc(Activity::getStartTime);

        Page<Activity> result = activityMapper.selectPage(new Page<>(safePage, safeSize), wrapper);

        List<ActivitySummaryResponse> list = result.getRecords().stream()
                .map(this::toSummary)
                .toList();

        return new PageResponse<>(result.getTotal(), safePage, safeSize, list);
    }

    @Override
    public ActivityDetailResponse getDetail(Long userId, Long activityId) {
        Activity activity = activityMapper.selectById(activityId);
        if (activity == null) {
            throw new BusinessException(ErrorCode.ACTIVITY_NOT_FOUND);
        }
        if (!activity.getUserId().equals(userId)) {
            throw new BusinessException(ErrorCode.ACTIVITY_FORBIDDEN);
        }

        ActivityDetailResponse response = new ActivityDetailResponse();
        response.setActivityId(activity.getId());
        response.setType(activity.getType());
        response.setMode(activity.getMode());
        response.setInvalid(activity.getInvalid());
        response.setDistanceMeters(activity.getDistanceMeters());
        response.setDurationSeconds(activity.getDurationSeconds());
        response.setAvgSpeed(activity.getAvgSpeed());
        response.setAvgPace(computeAvgPace(activity.getDurationSeconds(), activity.getDistanceMeters()));
        response.setCalories(activity.getCalories());
        response.setStartTime(activity.getStartTime());
        response.setEndTime(activity.getEndTime());
        response.setCreatedAt(activity.getCreatedAt());
        response.setTrack(parseTrack(activity.getTrackJson()));
        return response;
    }

    private void validate(ActivityCreateRequest request) {
        if (request.getType() == null || (request.getType() != 1 && request.getType() != 2)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "运动类型不合法");
        }
        if (request.getEndTime() <= request.getStartTime()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "结束时间必须晚于开始时间");
        }

        List<TrackPointRequest> track = request.getTrack();
        if (track == null || track.size() < 2) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "轨迹点数量不足");
        }
        int maxPoints = request.getType() == 2 ? MAX_CYCLING_POINTS : MAX_RUNNING_POINTS;
        if (track.size() > maxPoints) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "轨迹点数量超过上限");
        }

        for (TrackPointRequest p : track) {
            if (p.getLatitude() < -90 || p.getLatitude() > 90) {
                throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "纬度不合法");
            }
            if (p.getLongitude() < -180 || p.getLongitude() > 180) {
                throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "经度不合法");
            }
        }
    }

    private List<TrackPoint> toTrackPoints(List<TrackPointRequest> track) {
        List<TrackPoint> points = new ArrayList<>(track.size());
        for (TrackPointRequest p : track) {
            points.add(new TrackPoint(p.getLatitude(), p.getLongitude(), p.getTimestamp(), p.getAccuracy()));
        }
        return points;
    }

    private boolean isExclusiveMode(Integer mode) {
        return mode != null && mode == 2;
    }

    private ActivityCreateResponse buildCreateResponse(Activity activity, int durationSeconds) {
        ActivityCreateResponse response = new ActivityCreateResponse();
        response.setActivityId(activity.getId());
        response.setType(activity.getType());
        response.setMode(activity.getMode());
        response.setInvalid(activity.getInvalid());
        response.setDistanceMeters(activity.getDistanceMeters());
        response.setDurationSeconds(durationSeconds);
        response.setAvgSpeed(activity.getAvgSpeed());
        response.setAvgPace(computeAvgPace(durationSeconds, activity.getDistanceMeters()));
        response.setCalories(activity.getCalories());
        response.setStartTime(activity.getStartTime());
        response.setEndTime(activity.getEndTime());
        return response;
    }

    private ActivitySummaryResponse toSummary(Activity activity) {
        ActivitySummaryResponse response = new ActivitySummaryResponse();
        response.setActivityId(activity.getId());
        response.setType(activity.getType());
        response.setMode(activity.getMode());
        response.setInvalid(activity.getInvalid());
        response.setDistanceMeters(activity.getDistanceMeters());
        response.setDurationSeconds(activity.getDurationSeconds());
        response.setAvgSpeed(activity.getAvgSpeed());
        response.setAvgPace(computeAvgPace(activity.getDurationSeconds(), activity.getDistanceMeters()));
        response.setStartTime(activity.getStartTime());
        response.setEndTime(activity.getEndTime());
        response.setCreatedAt(activity.getCreatedAt());
        return response;
    }

    private Integer computeAvgPace(Integer durationSeconds, Integer distanceMeters) {
        if (durationSeconds == null || distanceMeters == null || distanceMeters == 0) {
            return null;
        }
        return (int) Math.round(durationSeconds * 1000.0 / distanceMeters);
    }

    private String serializeTrack(List<TrackPoint> track) {
        try {
            return objectMapper.writeValueAsString(track);
        } catch (JsonProcessingException e) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR);
        }
    }

    private List<TrackPoint> parseTrack(String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<TrackPoint>>() {
            });
        } catch (JsonProcessingException e) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR);
        }
    }

    private LocalDateTime toLocalDateTime(long epochMilli) {
        return LocalDateTime.ofInstant(Instant.ofEpochMilli(epochMilli), ZONE);
    }
}
