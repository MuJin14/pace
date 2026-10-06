package com.campusrun.server.dto.response;

import java.util.ArrayList;
import java.util.List;

/**
 * 历史数据修复的执行结果。
 *
 * <p>为什么要返回这么详细的数字：这是一次**不可逆的批量改写**，
 * 执行者必须能确认「改了多少、剩下多少没修好」。
 * 只返回一句「成功」在这种操作里是不负责任的 ——
 * 出问题时无从判断是被改坏了还是本来如此。
 */
public class DistanceRepairResult {

    /** 是否只做了预演（dry-run），未写库。 */
    private boolean dryRun;

    /** 扫描到的「距离为 0 但轨迹非空」的记录数。 */
    private int scannedZeroDistance;

    /** 用新算法重算后距离大于 0、因此被修正的记录数。 */
    private int fixedActivities;

    /** 重算后仍然为 0 的记录数（轨迹本身就没有有效位移，属于正常情况）。 */
    private int stillZero;

    /** 无法解析轨迹 JSON 而被跳过的记录数。 */
    private int unparsableTracks;

    /** 修正前的距离总和（米）。 */
    private long distanceBefore;

    /** 修正后的距离总和（米）。 */
    private long distanceAfter;

    /** user_stats 累计里程/次数被重算的用户数。 */
    private int rebuiltUserStats;

    /** 重建的排行榜 period 数（日 + 周 + 月 + rolling30d）。 */
    private int rebuiltLeaderboardPeriods;

    /** 重算进度的目标数。 */
    private int rebuiltGoals;

    /** 被修正的记录明细（上限 50 条，避免响应过大）。 */
    private List<Item> samples = new ArrayList<>();

    public static class Item {
        private long activityId;
        private long userId;
        private int oldDistance;
        private int newDistance;

        public Item() {
        }

        public Item(long activityId, long userId, int oldDistance, int newDistance) {
            this.activityId = activityId;
            this.userId = userId;
            this.oldDistance = oldDistance;
            this.newDistance = newDistance;
        }

        public long getActivityId() {
            return activityId;
        }

        public long getUserId() {
            return userId;
        }

        public int getOldDistance() {
            return oldDistance;
        }

        public int getNewDistance() {
            return newDistance;
        }
    }

    public boolean isDryRun() {
        return dryRun;
    }

    public void setDryRun(boolean dryRun) {
        this.dryRun = dryRun;
    }

    public int getScannedZeroDistance() {
        return scannedZeroDistance;
    }

    public void setScannedZeroDistance(int scannedZeroDistance) {
        this.scannedZeroDistance = scannedZeroDistance;
    }

    public int getFixedActivities() {
        return fixedActivities;
    }

    public void setFixedActivities(int fixedActivities) {
        this.fixedActivities = fixedActivities;
    }

    public int getStillZero() {
        return stillZero;
    }

    public void setStillZero(int stillZero) {
        this.stillZero = stillZero;
    }

    public int getUnparsableTracks() {
        return unparsableTracks;
    }

    public void setUnparsableTracks(int unparsableTracks) {
        this.unparsableTracks = unparsableTracks;
    }

    public long getDistanceBefore() {
        return distanceBefore;
    }

    public void setDistanceBefore(long distanceBefore) {
        this.distanceBefore = distanceBefore;
    }

    public long getDistanceAfter() {
        return distanceAfter;
    }

    public void setDistanceAfter(long distanceAfter) {
        this.distanceAfter = distanceAfter;
    }

    public int getRebuiltUserStats() {
        return rebuiltUserStats;
    }

    public void setRebuiltUserStats(int rebuiltUserStats) {
        this.rebuiltUserStats = rebuiltUserStats;
    }

    public int getRebuiltLeaderboardPeriods() {
        return rebuiltLeaderboardPeriods;
    }

    public void setRebuiltLeaderboardPeriods(int rebuiltLeaderboardPeriods) {
        this.rebuiltLeaderboardPeriods = rebuiltLeaderboardPeriods;
    }

    public int getRebuiltGoals() {
        return rebuiltGoals;
    }

    public void setRebuiltGoals(int rebuiltGoals) {
        this.rebuiltGoals = rebuiltGoals;
    }

    public List<Item> getSamples() {
        return samples;
    }

    public void setSamples(List<Item> samples) {
        this.samples = samples;
    }
}
