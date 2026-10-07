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

    /**
     * 允许「上报的开始时间」早于「第一个轨迹点」的最大间隔（秒）。
     *
     * <p>超过这个间隔就认为上报的开始时间是**陈旧的**，改用第一个轨迹点的时间。
     *
     * <h2>为什么需要这条（真实故障：一次正常跑步被判无效）</h2>
     *
     * 用户反馈：「跑了一下，原本是合格的时间，结果开始时间给我定位到昨天了，
     * 导致成绩无效」。
     *
     * 链路是这样的：
     * <ol>
     *   <li>上一次运动没跑完/没上传成功，本地留下草稿（含当时的 startedAt）；</li>
     *   <li>今天再开跑，草稿被恢复，`_startedAt` 被赋成**昨天**那个值；</li>
     *   <li>本次的轨迹点时间戳却是**今天**的；</li>
     *   <li>服务端按 {@code duration = endTime - startTime} 算时长 → 约 86400 秒；</li>
     *   <li>平均速度 = 距离 / 24 小时 ≈ 0 → 命中 STATIONARY_DRIFT
     *       「疑似原地漂移」→ **整次成绩无效**。</li>
     * </ol>
     *
     * <p>关键在于：轨迹点的时间戳是**这次真实采集**的，比客户端上报的
     * 开始时间可信得多。所以当两者差得离谱时，信轨迹。
     *
     * <p>取 10 分钟：正常情况下的间隔只有「冷启动搜星」那几秒到几十秒；
     * 10 分钟既不会误伤（真在操场上等了十分钟才开始记轨迹也说得过去），
     * 又远小于「跨天」这种量级。
     */
    public static final long MAX_START_TIME_GAP_SECONDS = 600L;

    /**
     * 修正客户端上报的开始时间。
     *
     * <p>返回**应当采用的**开始时间（毫秒）。规则：
     * <ul>
     *   <li>轨迹里拿不到时间 → 原样返回（无从校正）；</li>
     *   <li>上报时间**晚于**第一个点 → 也采用第一个点（开始时间不能晚于第一次记录，
     *       否则时长会被压缩，配速虚高）；</li>
     *   <li>上报时间早于第一个点、但间隔在 {@link #MAX_START_TIME_GAP_SECONDS} 内
     *       → 保留上报值（那几秒是真实的「点开 App → 等到定位」的间隔，
     *       用户认可这段时间）；</li>
     *   <li>早得超过阈值 → 判为陈旧值（草稿恢复导致），改用第一个点的时间。</li>
     * </ul>
     *
     * <p>做成静态纯函数是为了能直接单测 —— 这个判定只看代码不容易发现错，
     * 而它一旦出错就是「用户的成绩被静默作废」或「时长虚高」，两者都很难排查。
     *
     * @param track            轨迹点（按时间升序，可为空）
     * @param reportedStartMs  客户端上报的开始时间（毫秒）
     * @return 应当采用的开始时间（毫秒）
     */
    public static long effectiveStartTimeMillis(List<TrackPoint> track,
                                                long reportedStartMs) {
        Long firstPointMs = firstPointTimestamp(track);
        if (firstPointMs == null) {
            return reportedStartMs;
        }
        long gapMillis = firstPointMs - reportedStartMs;
        // 上报时间晚于第一个点：以第一个点为准（时长不能被压缩）
        if (gapMillis < 0) {
            return firstPointMs;
        }
        long gapSeconds = gapMillis / 1000L;
        if (gapSeconds > MAX_START_TIME_GAP_SECONDS) {
            return firstPointMs;
        }
        return reportedStartMs;
    }

    /** 轨迹里第一个带时间戳的点的时间；没有则返回 null。 */
    private static Long firstPointTimestamp(List<TrackPoint> track) {
        if (track == null) {
            return null;
        }
        for (TrackPoint p : track) {
            if (p != null && p.getTimestamp() != null) {
                return p.getTimestamp();
            }
        }
        return null;
    }

    /**
     * 决定这次运动该采用哪个时长。
     *
     * <h2>背景</h2>
     *
     * 原来只用 {@code endTime - startTime}。一次连续跑完没问题，但**续接场景会算错**：
     * 客户端恢复本地草稿继续跑时，累计时长是一段段跑出来的，
     * 而「结束 − 开始」把中间没在跑的空档也算了进去。
     *
     * 真实故障：上报时长 17.9 小时（实际只跑了十几分钟）→ 平均速度算成 0 →
     * 命中 STATIONARY_DRIFT「疑似原地漂移」→ 整次成绩作废。
     *
     * <h2>规则</h2>
     *
     * 客户端上报了 {@code reportedSeconds}（它自己计时器上的数字，最贴近用户认知）
     * 时优先采用，但**必须不超过轨迹覆盖的时间跨度** —— 时长不可能长于轨迹本身。
     * 超出说明上报值不可信（客户端 bug 或伪造），退回时间戳相减。
     *
     * <p>这条约束同时让伪造没有收益：把时长报大只会拉低平均速度，
     * 反而更容易被判成漂移。
     *
     * @param reportedSeconds 客户端上报的时长（秒）；null/非正数表示没报
     * @param timelineSeconds 时间戳相减得到的时长（秒）
     * @param spanSeconds     轨迹首末点的时间跨度（秒）；&lt;=0 表示无法判定
     * @return 应当采用的时长（秒），保证 &gt; 0
     */
    public static long effectiveDurationSeconds(Integer reportedSeconds,
                                               long timelineSeconds,
                                               long spanSeconds) {
        if (reportedSeconds == null || reportedSeconds <= 0) {
            // 老版本客户端不传，或传了非法值：退回时间戳相减
            return Math.max(timelineSeconds, 1);
        }
        // 无法用轨迹校验（点太少/没有时间戳）时以时间戳相减为准，
        // 宁可短一点（配速偏高）也不能凭空接受一个未经校验的大值。
        if (spanSeconds <= 0) {
            return Math.max(timelineSeconds, 1);
        }
        if (reportedSeconds > spanSeconds) {
            return Math.max(timelineSeconds, 1);
        }
        return Math.max(reportedSeconds, 1);
    }

    /** 轨迹首末点之间的时间跨度（秒）；无法判定时返回 0。 */
    public static long trackSpanSeconds(List<TrackPoint> track) {
        if (track == null || track.size() < 2) {
            return 0;
        }
        Long first = null;
        Long last = null;
        for (TrackPoint p : track) {
            if (p == null || p.getTimestamp() == null) {
                continue;
            }
            if (first == null) {
                first = p.getTimestamp();
            }
            last = p.getTimestamp();
        }
        if (first == null || last == null || last <= first) {
            return 0;
        }
        return (last - first) / 1000L;
    }

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
