package com.campusrun.server.util;

import com.campusrun.server.model.TrackPoint;

import java.util.List;

public final class GpsUtil {

    private static final double EARTH_RADIUS_METERS = 6_371_000.0;

    private GpsUtil() {
    }

    public static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_METERS * c;
    }

    public static double totalDistanceMeters(List<TrackPoint> track) {
        if (track == null || track.size() < 2) {
            return 0.0;
        }
        double total = 0.0;
        for (int i = 1; i < track.size(); i++) {
            TrackPoint prev = track.get(i - 1);
            TrackPoint curr = track.get(i);
            total += distanceMeters(prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
        }
        return total;
    }

    /**
     * 精度阈值（米）。误差大于它的点直接不参与累加。
     *
     * <p>为什么必须过滤：手机在楼下、树荫、高楼间时误差常到 20-50 米，
     * 这种点会让轨迹"跳"出去再跳回来，一次抖动就凭空产生上百米。
     * 实测同一条路线，不过滤精度能比真实距离多算 2-3 倍 —— 用户会觉得
     * 「定位不准」，其实是脏点被当成真实位移了。
     */
    public static final double MAX_ACCURACY_METERS = 35.0;

    /**
     * 方向一致性判据的窗口长度（秒）。
     *
     * <p>窗口太短信息量不够（单段位移无法区分慢走与抖动）；
     * 太长会让「折返跑/绕圈」这类真实路线被判成不直。
     * 5 秒是实测的折中：慢走能攒够位移，抖动又漂不出方向性。
     */
    public static final double COHERENCE_WINDOW_SECONDS = 5.0;

    /**
     * 窗口内「净位移 ÷ 路径长度」的最低值。低于它视为 GPS 抖动，不计入距离。
     *
     * <p>真实走直线时该比值接近 1；静止抖动来回漂移时路径长度不断累加、
     * 净位移被限制在抖动幅度内，比值通常远低于 0.5。
     * 取 0.6 是留出余量：轻微绕行、过弯、GPS 噪声都不会误伤。
     */
    public static final double MIN_STRAIGHTNESS = 0.6;

    /**
     * 相邻点最小计入位移（米）。
     *
     * @deprecated 已被滑窗方向一致性判据（{@link #COHERENCE_WINDOW_SECONDS} +
     *     {@link #MIN_STRAIGHTNESS}）取代。保留常量只为兼容既有引用。
     *
     *     <p>⚠️ **这个值曾经是 2.0，正是「运动记录距离为 0」的根因**：
     *     旧判据是「位移 &lt; 2 米 <b>且</b> 间隔 &lt; 5 秒 → 丢弃」，
     *     而 geolocator 在多数机型上是 1 秒采样 ——
     *     慢走 1.4 m/s × 1 秒 = 1.40 米、慢跑 2.0 m/s × 1 秒 = 2.00 米
     *     （严格小于 2 也算丢弃），两支都命中，
     *     于是**每一段都被丢弃、整条轨迹距离恰好为 0**。
     *     这解释了「为什么只有部分账号为 0」：取决于**速度**，
     *     与账号无关 —— 走路的人全为 0，跑步（3 m/s）的人全部正常。
     */
    @Deprecated
    public static final double MIN_SEGMENT_METERS = 2.0;

    /**
     * 计入位移所需的最小等效速度（米/秒）。
     *
     * @deprecated 单段速度无法区分「慢走 1.4 m/s」与「静止抖动 2 m/s」，
     *     已被滑窗方向一致性判据取代。
     */
    @Deprecated
    public static final double MIN_SEGMENT_SPEED_MPS = 0.5;

    /**
     * 小位移仍采信的时长门槛（秒）。
     *
     * @deprecated 已被滑窗方向一致性判据取代。
     *     保留常量只为兼容既有引用；新逻辑不再使用固定秒数判据。
     */
    @Deprecated
    public static final double MIN_SEGMENT_SECONDS_FOR_SLOW = 5.0;

    /**
     * 精度加权后的总距离。
     *
     * <p>与 {@link #totalDistanceMeters} 的区别：跳过精度差的点（不采信其位移），
     * 并滤掉 GPS 静止抖动。
     *
     * <p>跳过（而不是修正）是刻意的：修正一个误差 50 米的点需要引入状态估计，
     * 收益不确定；而跳过最坏只是漏算一小段（用户不吃亏），
     * 采信却会凭空多算几百米（对整个排行榜不公平）。
     *
     * <p><b>为什么不能再用「逐段位移阈值」</b>：单段位移无法区分
     * 「慢走 1.4 m/s（每步 1.4 米）」和「静止抖动（每步可达 2 米）」——
     * 两者单步位移处在同一量级。旧实现要求「位移 ≥ 2 米 或 间隔 ≥ 5 秒」，
     * 在 1 秒采样下慢走**两支都不满足**，于是每段都被丢弃、
     * 整条轨迹距离<b>恰好为 0</b>（线上「运动记录为 0」的真实根因）。
     *
     * <p>现在的做法是<b>滑窗方向一致性</b>：在 {@link #COHERENCE_WINDOW_SECONDS}
     * 秒的窗口内分别累计「净位移」与「路径长度」，只有
     * 净位移 ÷ 路径长度 ≥ {@link #MIN_STRAIGHTNESS}
     * 才认这是真实移动。
     * <ul>
     *   <li>真实走直线：净位移 ≈ 路径长度 → 比值接近 1 → 计入</li>
     *   <li>静止抖动：来回漂移使路径长度不断累加、净位移却被限制在
     *       抖动幅度内 → 比值很低 → 滤掉</li>
     * </ul>
     * 这个判据对<b>速度不敏感</b>，因此慢走与快跑一视同仁，
     * 也不会因为采样间隔从 1 秒变 5 秒而改变结论。
     */
    public static double totalDistanceMetersFiltered(List<TrackPoint> track) {
        if (track == null || track.size() < 2) {
            return 0.0;
        }
        DistanceAccumulator acc = new DistanceAccumulator();
        for (TrackPoint p : track) {
            if (p == null || p.getLatitude() == null || p.getLongitude() == null) {
                continue;
            }
            if (isAccuracyTooPoor(p)) {
                // 脏点不采信，也不进入窗口（否则会拿脏点算出一大段位移）
                continue;
            }
            acc.add(p);
        }
        return acc.total();
    }

    /**
     * 滑窗方向一致性累加器。
     *
     * <p>维护一个 {@link #COHERENCE_WINDOW_SECONDS} 秒的滑动窗口：
     * <ul>
     *   <li>窗口未满：先攒着，不急于下结论（单段位移信息量太少）；</li>
     *   <li>窗口已满：用「锚点 → 当前点」的**弦长**作为净位移，
     *       与窗口内**路径长度**比较；比值够高就计入弦长并把锚点推进到当前点，
     *       否则丢弃并同样推进锚点（避免基准冻结）。</li>
     * </ul>
     *
     * <p>用弦长而不是路径长度累加，是刻意的保守选择：路径长度会把
     * GPS 噪声也算进去（略偏大），弦长则是这段真实位移的下界。
     * 少算一点用户不吃亏，多算会让排行榜不公平。
     */
    static final class DistanceAccumulator {
        private final List<TrackPoint> window = new java.util.ArrayList<>();
        private TrackPoint anchor;
        private double total;

        void add(TrackPoint p) {
            if (anchor == null) {
                anchor = p;
                window.add(p);
                return;
            }
            window.add(p);
            Long tAnchor = anchor.getTimestamp();
            Long tCurr = p.getTimestamp();
            // 时间戳缺失或时间倒流：退化处理，直接按弦长累加（保持老数据的向后兼容）
            if (tAnchor == null || tCurr == null || tCurr <= tAnchor) {
                total += chord(anchor, p);
                anchor = p;
                window.clear();
                window.add(p);
                return;
            }
            double elapsed = (tCurr - tAnchor) / 1000.0;
            if (elapsed < COHERENCE_WINDOW_SECONDS) {
                return; // 窗口未满，继续攒
            }
            double net = chord(anchor, p);
            double path = 0.0;
            for (int i = 1; i < window.size(); i++) {
                path += chord(window.get(i - 1), window.get(i));
            }
            // 路径长度为 0 表示位置完全没变（真静止），此时 net 也是 0，
            // 直接丢弃即可，不要因为 0/0 产生 NaN 判定。
            boolean coherent = path > 0 && net / path >= MIN_STRAIGHTNESS;
            if (coherent && net > 0) {
                total += net;
            }
            anchor = p;
            window.clear();
            window.add(p);
        }

        double total() {
            // 收尾：窗口里还剩一段没结算（尾段不足一个窗口），
            // 用剩下的点按同样的判据结算一次，避免最后几百米被丢掉。
            if (anchor != null && window.size() >= 2) {
                TrackPoint lastPoint = window.get(window.size() - 1);
                double net = chord(anchor, lastPoint);
                double path = 0.0;
                for (int i = 1; i < window.size(); i++) {
                    path += chord(window.get(i - 1), window.get(i));
                }
                if (path > 0 && net / path >= MIN_STRAIGHTNESS && net > 0) {
                    total += net;
                }
            }
            return total;
        }

        private static double chord(TrackPoint a, TrackPoint b) {
            return distanceMeters(a.getLatitude(), a.getLongitude(),
                    b.getLatitude(), b.getLongitude());
        }
    }

    /**
     * 一段位移是否计入总距离（**已废弃**）。
     *
     * @deprecated 逐段阈值无法区分「慢走 1.4 m/s」与「静止抖动 2 m/s」，
     *     旧实现（阈值 2 米 / 5 秒）在 1 秒采样下会把慢走的每一段都丢掉，
     *     导致整条轨迹距离为 0。请使用
     *     {@link #totalDistanceMetersFiltered} 的滑窗方向一致性判据。
     */
    @Deprecated
    static boolean shouldCountSegment(double segmentMeters, TrackPoint from, TrackPoint to) {
        if (segmentMeters >= MIN_SEGMENT_METERS) {
            return true;
        }
        Long t1 = from.getTimestamp();
        Long t2 = to.getTimestamp();
        if (t1 == null || t2 == null) {
            return false;
        }
        double seconds = (t2 - t1) / 1000.0;
        if (seconds <= 0) {
            return false;
        }
        return segmentMeters / seconds >= MIN_SEGMENT_SPEED_MPS;
    }

    /** 精度缺失时不做判断（老数据可能没有 accuracy 字段）。 */
    public static boolean isAccuracyTooPoor(TrackPoint p) {
        Double acc = p.getAccuracy();
        return acc != null && acc > MAX_ACCURACY_METERS;
    }
}
