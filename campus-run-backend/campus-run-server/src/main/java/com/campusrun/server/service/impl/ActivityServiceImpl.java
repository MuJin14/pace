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
import com.campusrun.server.util.TrackAnomalyDetector;
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

    /**
     * 计算距离 → 专属模式围栏校验 → 落库 → 有效记录联动排行榜/目标/勋章。
     */
    @Override
    @Transactional
    public ActivityCreateResponse create(Long userId, ActivityCreateRequest request) {
        validate(request);

        List<TrackPoint> track = toTrackPoints(request.getTrack());
        // 用「精度过滤后」的距离作为成绩口径：脏点会让距离虚高数倍，
        // 直接采信会让排行榜失真，用户也会觉得"定位不准"。
        double distance = GpsUtil.totalDistanceMetersFiltered(track);
        double rawDistance = GpsUtil.totalDistanceMeters(track);
        if (distance <= 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(), "轨迹距离为 0");
        }
        if (rawDistance > distance * 1.5) {
            // 脏点占比较高：记录下来，便于定位"用户反馈不准"的真实原因
            log.warn("轨迹精度较差，过滤后距离大幅缩小：raw={}m filtered={}m points={}",
                    Math.round(rawDistance), Math.round(distance), track.size());
        }

        // ⚠️⚠️ 先用「第一个轨迹点」校正上报的开始时间，**再**算时长。
        //
        // 真实故障：用户一次正常跑步被判无效 —— 「开始时间给我定位到昨天了」。
        // 原因是客户端恢复了上一次没上传完的本地草稿，把 startedAt 带成了昨天，
        // 而轨迹点的时间戳是今天的。于是 duration = endTime - startTime ≈ 24 小时，
        // 平均速度趋近 0，命中 STATIONARY_DRIFT「疑似原地漂移」，成绩作废。
        //
        // 轨迹点的时间戳是这次真实采集的，比客户端上报的开始时间可信；
        // 两者差得离谱时以轨迹为准。判定与阈值见 TrackAnomalyDetector。
        long effectiveStartMs = TrackAnomalyDetector.effectiveStartTimeMillis(
                track, request.getStartTime());
        if (effectiveStartMs != request.getStartTime()) {
            log.warn("上报的开始时间与轨迹首点差距过大，已按轨迹首点校正："
                            + "userId={}, reported={}, firstPoint={}, 相差={}秒",
                    userId, request.getStartTime(), effectiveStartMs,
                    Math.abs(effectiveStartMs - request.getStartTime()) / 1000);
        }

        long durationSeconds = (request.getEndTime() - effectiveStartMs) / 1000;

        // ⚠️ 时长优先采用客户端计时器上报的值（若有），并用轨迹跨度做上限校验。
        //
        // 为什么不能只用「结束 − 开始」：客户端续接本地草稿继续跑时，
        // 累计时长是一段段跑出来的，而时间戳相减会把中间没在跑的空档也算进去。
        // 真实故障：上报时长 17.9 小时（实际跑了十几分钟）→ 平均速度算成 0
        // → 命中「疑似原地漂移」→ 整次成绩作废。
        // 判定规则与约束见 TrackAnomalyDetector.effectiveDurationSeconds。
        long spanSeconds = TrackAnomalyDetector.trackSpanSeconds(track);
        long rawDurationSeconds = durationSeconds;
        durationSeconds = TrackAnomalyDetector.effectiveDurationSeconds(
                request.getDurationSeconds(), durationSeconds, spanSeconds);
        if (durationSeconds != rawDurationSeconds) {
            log.info("时长按客户端上报值校正：userId={}, 时间戳相减={}s, "
                            + "客户端上报={}s, 轨迹跨度={}s, 采用={}s",
                    userId, rawDurationSeconds, request.getDurationSeconds(),
                    spanSeconds, durationSeconds);
        }

        double avgSpeedKmh = (distance / 1000.0) / (durationSeconds / 3600.0);

        int mode = request.getMode() == null ? 1 : request.getMode();
        int distanceMeters = (int) Math.round(distance);
        log.info("创建运动记录，userId={}, type={}, mode={}, trackPoints={}, distanceMeters={}",
                userId, request.getType(), mode, track.size(), distanceMeters);

        Activity activity = new Activity();
        activity.setUserId(userId);
        activity.setType(request.getType());
        activity.setMode(mode);
        activity.setDistanceMeters(distanceMeters);
        activity.setDurationSeconds((int) durationSeconds);
        activity.setAvgSpeed(BigDecimal.valueOf(avgSpeedKmh).setScale(2, RoundingMode.HALF_UP));
        activity.setCalories(request.getCalories() == null
                ? null
                : BigDecimal.valueOf(request.getCalories()).setScale(2, RoundingMode.HALF_UP));
        // 存校正后的值：榜单/目标/勋章都按 startTime 归属日期，
        // 存陈旧值会让这次运动被算到「昨天」那一栏去。
        activity.setStartTime(toLocalDateTime(effectiveStartMs));
        activity.setEndTime(toLocalDateTime(request.getEndTime()));

        TrackPoint first = track.get(0);
        TrackPoint last = track.get(track.size() - 1);
        activity.setStartLat(BigDecimal.valueOf(first.getLatitude()));
        activity.setStartLng(BigDecimal.valueOf(first.getLongitude()));
        activity.setEndLat(BigDecimal.valueOf(last.getLatitude()));
        activity.setEndLng(BigDecimal.valueOf(last.getLongitude()));

        activity.setTrackJson(serializeTrack(track));

        // 反作弊第一道闸门：先做轨迹物理合理性校验（与是否专属模式无关，普通跑步同样要查）。
        // 命中则标记无效并记录原因；无效记录仍会入库，便于人工复核与阈值调参，
        // 但不会计入排行榜/目标进度/勋章（见下方 invalid 判断）。
        TrackAnomalyDetector.Anomaly anomaly = TrackAnomalyDetector.detect(
                track,
                request.getType(),
                distance,
                durationSeconds,
                effectiveStartMs,
                System.currentTimeMillis());
        if (anomaly != null) {
            activity.setInvalid(1);
            activity.setInvalidReason(anomaly.message());
            log.warn("轨迹反作弊命中，userId={}, type={}, anomaly={}, distanceMeters={}, durationSeconds={}",
                    userId, request.getType(), anomaly.name(), distanceMeters, durationSeconds);
        }

        // 专属模式再叠加围栏校验；两者取「或」——任一项判无效即为无效。
        if (isExclusiveMode(activity.getMode())) {
            FenceMatchResult match = fenceService.evaluate(track);
            activity.setFenceId(match.fenceId());
            activity.setOutsideRatio(match.outsideRatio());
            if (match.invalid()) {
                activity.setInvalid(1);
                if (activity.getInvalidReason() == null) {
                    activity.setInvalidReason("轨迹在校园围栏内的比例不足");
                }
            }
            if (match.fenceId() != null || match.invalid()) {
                log.info("围栏校验命中，fenceId={}, outsideRatio={}, invalid={}",
                        match.fenceId(), match.outsideRatio(), match.invalid());
            }
        }

        if (activity.getInvalid() == null) {
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

        log.info("创建运动记录完成，activityId={}, invalid={}, invalidReason={}",
                activity.getId(), activity.getInvalid(), activity.getInvalidReason());
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

        // ⚠️ 结束时间必须晚于**第一个轨迹点**，而不是晚于「上报的开始时间」。
        //
        // 上报的开始时间可能是客户端恢复了本地草稿带过来的陈旧值
        // （用户反馈过「开始时间被定位到昨天」）。如果拿它做门槛，
        // 就会出现两种误伤：
        //   · 草稿时间在未来 → endTime 明明正常，却被判「结束时间必须晚于开始时间」，
        //     而且文案完全指不到真正的问题；
        //   · 真正的判据其实是「得有一段正的真实轨迹」。
        //
        // 用轨迹首点做判据既准确又不会被陈旧值带偏 —— 轨迹点的时间戳
        // 是这次真实采集的。开始时间本身则由 effectiveStartTimeMillis 校正。
        Long firstPointMs = null;
        for (TrackPointRequest p : track) {
            if (p.getTimestamp() != null) {
                firstPointMs = p.getTimestamp();
                break;
            }
        }
        if (firstPointMs != null && request.getEndTime() <= firstPointMs) {
            throw new BusinessException(ErrorCode.PARAM_ERROR.getCode(),
                    "结束时间必须晚于第一个轨迹点的时间");
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
        response.setInvalidReason(activity.getInvalidReason());
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
