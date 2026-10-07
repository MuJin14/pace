package com.campusrun.server.dto.request;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.util.List;

public class ActivityCreateRequest {

    @NotNull(message = "运动类型不能为空")
    @Min(value = 1, message = "运动类型不合法")
    @Max(value = 2, message = "运动类型不合法")
    private Integer type;

    @Min(value = 1, message = "模式不合法")
    @Max(value = 2, message = "模式不合法")
    private Integer mode;

    @NotNull(message = "开始时间不能为空")
    private Long startTime;

    @NotNull(message = "结束时间不能为空")
    private Long endTime;

    /**
     * 客户端计时器给出的**真实运动时长**（秒）。可选。
     *
     * <h2>为什么需要它</h2>
     *
     * 原来服务端只用 {@code endTime - startTime} 当时长。一次连续跑完时没问题，
     * 但**续接场景会算错**：客户端恢复本地草稿继续跑时，累计时长是一段段跑出来的，
     * 而「结束 − 开始」把中间没在跑的空档也算进去了。
     *
     * 真实故障（用户反馈「跑了一下，开始时间被定位到昨天，成绩无效」）：
     * 上报的时长是 17.9 小时，实际运动只有十几分钟 —— 平均速度被算成 0，
     * 命中「疑似原地漂移」，整次成绩作废。
     *
     * 客户端**手里就有准确值**（它显示的计时就是它），让它直接上报，
     * 服务端不必再从两个时间戳反推。
     *
     * <h2>为什么不无条件采信</h2>
     *
     * 客户端数据不可信，所以只在「不超过轨迹真实时间跨度」时才采用 ——
     * 时长不可能长于轨迹覆盖的时间。这条约束也让伪造没有收益：
     * 报得越长平均速度越低，只会把自己判成漂移。
     *
     * 老版本客户端不传这个字段，走原来的时间戳相减逻辑。
     */
    @PositiveOrZero(message = "运动时长不能为负")
    private Integer durationSeconds;

    @PositiveOrZero(message = "卡路里不能为负")
    private Double calories;

    @NotEmpty(message = "轨迹点不能为空")
    @Size(min = 2, max = 15000, message = "轨迹点数量需在 2-15000 之间")
    private List<@Valid TrackPointRequest> track;

    public Integer getType() {
        return type;
    }

    public void setType(Integer type) {
        this.type = type;
    }

    public Integer getMode() {
        return mode;
    }

    public void setMode(Integer mode) {
        this.mode = mode;
    }

    public Long getStartTime() {
        return startTime;
    }

    public void setStartTime(Long startTime) {
        this.startTime = startTime;
    }

    public Long getEndTime() {
        return endTime;
    }

    public void setEndTime(Long endTime) {
        this.endTime = endTime;
    }

    public Integer getDurationSeconds() {
        return durationSeconds;
    }

    public void setDurationSeconds(Integer durationSeconds) {
        this.durationSeconds = durationSeconds;
    }

    public Double getCalories() {
        return calories;
    }

    public void setCalories(Double calories) {
        this.calories = calories;
    }

    public List<TrackPointRequest> getTrack() {
        return track;
    }

    public void setTrack(List<TrackPointRequest> track) {
        this.track = track;
    }
}
