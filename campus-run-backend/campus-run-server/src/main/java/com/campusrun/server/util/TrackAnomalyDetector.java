package com.campusrun.server.util;

import java.util.List;

import com.campusrun.server.model.TrackPoint;

/**
 * 轨迹异常检测：服务端反作弊的第一道闸门。
 *
 * <p>背景：客户端上传的轨迹完全不可信（可被篡改、可被脚本伪造），而榜单、目标进度、
 * 勋章都依赖「距离」这一个数字。因此在落库前必须做物理合理性校验：一个 5 公里跑出
 * 6000 km/h 的记录不该进榜。
 *
 * <p>设计要点：
 * <ul>
 *   <li>阈值取「人类极限 + 明显冗余」，宁可放过可疑样本也不误杀真实用户
 *       （真实用户被误判为无效的伤害远大于个别作弊者漏网）。</li>
 *   <li>速度上限取的是**全程平均速度**口径，而非瞬时；对运动中短时冲刺留足余量。</li>
 *   <li>检测只做「是否有效」判定与原因标记，不抛异常、不拒绝入库——
 *       无效记录仍然保留，便于人工复核与后续调参。</li>
 * </ul>
 */
public final class TrackAnomalyDetector {

    /** 跑步：全程平均速度上限（km/h）。人类马拉松约 20，短冲瞬时约 37，取 30 作为全程均值上限。 */
    private static final double MAX_AVG_SPEED_RUNNING_KMH = 30.0;

    /** 骑行：全程平均速度上限（km/h）。业余骑行巡航 20-30、下坡冲刺可到 60，取 60。 */
    private static final double MAX_AVG_SPEED_CYCLING_KMH = 60.0;

    /** 相邻两点之间允许的最大瞬时速度（km/h）。用于抓 GPS 瞬移：真跑不可能 80 km/h。 */
    private static final double MAX_SEGMENT_SPEED_RUNNING_KMH = 45.0;
    private static final double MAX_SEGMENT_SPEED_CYCLING_KMH = 90.0;

    /**
     * 相邻两点间允许的最大加速度（m/s²）。
     *
     * <p>⚠️ 这里必须比较**相邻两段的平均速度之差**，不能拿「一段速度 ÷ 该段时长」当作加速度。
     * 后者在物理上不成立：GPS 采样间隔常在 0.2-1 秒波动，按那个写法
     * 正常跑步（3 m/s、间隔 0.3 秒）就会得出 10 m/s² 而被误判成作弊，
     * 骑行更快、间隔更短，几乎必然命中。
     * 加速度的正确定义是速度变化率：Δv / Δt，且 Δt 要取两段之间的时间。
     */
    private static final double MAX_SEGMENT_ACCELERATION_MPS2 = 8.0;

    /**
     * 相邻两点最小时长（秒）。短于它的时段速度噪声极大（1 米误差在 0.1 秒内
     * 就是 10 m/s），不参与速度与加速度判定。
     */
    private static final double MIN_SEGMENT_SECONDS = 0.4;

    /** 有效轨迹的最小平均速度（m/s）。低于此值说明是原地漂移攒距离，而非真实位移。 */
    private static final double MIN_AVG_SPEED_MPS = 0.83; // ≈ 3 km/h

    /** 判定为「原地漂移」所需的最小距离与最小时长，避免误伤正常慢走/热身。 */
    private static final double MIN_DISTANCE_FOR_DRIFT_CHECK_METERS = 300.0;
    private static final long MIN_DURATION_FOR_DRIFT_CHECK_SECONDS = 60L;

    /** 允许的客户端时钟超前量（秒）：服务器时间 + 该值之后视为伪造未来时间。 */
    private static final long MAX_CLOCK_SKEW_SECONDS = 120L;

    /** 异常类型；{@link #message()} 会写入 activity.invalid_reason 供人工复核。 */
    public enum Anomaly {
        POINTS_TOO_FEW("轨迹点不足 2 个"),
        NON_POSITIVE_DURATION("运动时长必须大于 0"),
        FUTURE_START_TIME("开始时间超出了允许的时钟偏差"),
        DUPLICATE_TIMESTAMP_WITH_MOVE("相邻轨迹点时间相同但位置发生移动"),
        SEGMENT_SPEED_TOO_HIGH("相邻轨迹点瞬时速度超出物理上限"),
        SEGMENT_ACCELERATION_TOO_HIGH("相邻轨迹点加速度超出物理上限"),
        AVG_SPEED_TOO_HIGH("全程平均速度超出该运动类型的物理上限"),
        STATIONARY_DRIFT("距离与时长严重不匹配，疑似原地漂移攒距离");

        private final String message;

        Anomaly(String message) {
            this.message = message;
        }

        public String message() {
            return message;
        }
    }

    private TrackAnomalyDetector() {
    }

    /**
     * 检测轨迹是否物理合理。
     *
     * @param track          轨迹点（按时间升序）
     * @param type           运动类型：1=跑步 2=骑行
     * @param distanceMeters 服务端算出的总距离（米）
     * @param durationSeconds 服务端算出的总时长（秒）
     * @param startTimeMillis 客户端上报的开始时间（毫秒）
     * @param nowMillis      服务器当前时间（毫秒）
     * @return 首个命中的异常；完全正常时返回 {@code null}
     */
    public static Anomaly detect(List<TrackPoint> track,
                                 int type,
                                 double distanceMeters,
                                 long durationSeconds,
                                 long startTimeMillis,
                                 long nowMillis) {
        if (track == null || track.size() < 2) {
            return Anomaly.POINTS_TOO_FEW;
        }
        if (durationSeconds <= 0) {
            return Anomaly.NON_POSITIVE_DURATION;
        }
        if (startTimeMillis > nowMillis + MAX_CLOCK_SKEW_SECONDS * 1000L) {
            return Anomaly.FUTURE_START_TIME;
        }

        boolean cycling = type == 2;
        double maxSegmentSpeedKmh = cycling ? MAX_SEGMENT_SPEED_CYCLING_KMH : MAX_SEGMENT_SPEED_RUNNING_KMH;
        double maxAvgSpeedKmh = cycling ? MAX_AVG_SPEED_CYCLING_KMH : MAX_AVG_SPEED_RUNNING_KMH;

        // 上一段的平均速度与结束时刻，用于正确地算加速度（Δv / Δt）
        Double prevSegmentSpeedMps = null;
        Long prevSegmentEndMillis = null;

        for (int i = 1; i < track.size(); i++) {
            TrackPoint prev = track.get(i - 1);
            TrackPoint curr = track.get(i);
            if (!hasPositionAndTime(prev) || !hasPositionAndTime(curr)) {
                continue;
            }
            // 精度差的点不参与判定：脏点本来就该被距离计算忽略，
            // 拿它去判作弊会误伤正常用户。
            if (GpsUtil.isAccuracyTooPoor(prev) || GpsUtil.isAccuracyTooPoor(curr)) {
                continue;
            }
            double segmentMeters = GpsUtil.distanceMeters(
                    prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
            long deltaMillis = curr.getTimestamp() - prev.getTimestamp();

            if (deltaMillis <= 0) {
                // 时间未前进却发生了位移：GPS 抖动或伪造。
                // 阈值放到 5 米：静止时的正常抖动也可能有 2-3 米，1 米过于敏感。
                if (segmentMeters > 5.0) {
                    return Anomaly.DUPLICATE_TIMESTAMP_WITH_MOVE;
                }
                continue;
            }

            double deltaSeconds = deltaMillis / 1000.0;
            if (deltaSeconds < MIN_SEGMENT_SECONDS) {
                // 间隔太短：速度噪声过大，不参与速度/加速度判定，
                // 但时间基准仍要传递下去，否则下一段无法算 Δt
                prevSegmentEndMillis = curr.getTimestamp();
                continue;
            }

            double segmentSpeedMps = segmentMeters / deltaSeconds;
            if (segmentSpeedMps * 3.6 > maxSegmentSpeedKmh) {
                return Anomaly.SEGMENT_SPEED_TOO_HIGH;
            }

            // 加速度 = 速度变化 / 两段之间的时间（不是「速度 / 本段时长」）
            if (prevSegmentSpeedMps != null && prevSegmentEndMillis != null) {
                double dtSeconds = (curr.getTimestamp() - prevSegmentEndMillis) / 1000.0;
                if (dtSeconds >= MIN_SEGMENT_SECONDS) {
                    double accel = Math.abs(segmentSpeedMps - prevSegmentSpeedMps) / dtSeconds;
                    if (accel > MAX_SEGMENT_ACCELERATION_MPS2) {
                        return Anomaly.SEGMENT_ACCELERATION_TOO_HIGH;
                    }
                }
            }
            prevSegmentSpeedMps = segmentSpeedMps;
            prevSegmentEndMillis = curr.getTimestamp();
        }

        // 平均速度用调用方传入的 distanceMeters 判定。
        // 调用方（ActivityServiceImpl）必须传**精度过滤后**的距离，
        // 也就是最终计入成绩的那个值 —— 判定口径与成绩口径不一致会导致
        // 自相矛盾：一段 GPS 漂移把原始距离推到 100+ km/h，
        // 用户明明跑了 5 公里却被判「超速作弊」。
        double avgSpeedMps = distanceMeters / durationSeconds;
        if (avgSpeedMps * 3.6 > maxAvgSpeedKmh) {
            return Anomaly.AVG_SPEED_TOO_HIGH;
        }
        if (distanceMeters >= MIN_DISTANCE_FOR_DRIFT_CHECK_METERS
                && durationSeconds >= MIN_DURATION_FOR_DRIFT_CHECK_SECONDS
                && avgSpeedMps < MIN_AVG_SPEED_MPS) {
            return Anomaly.STATIONARY_DRIFT;
        }
        return null;
    }

    private static boolean hasPositionAndTime(TrackPoint p) {
        return p != null
                && p.getLatitude() != null
                && p.getLongitude() != null
                && p.getTimestamp() != null;
    }
}
