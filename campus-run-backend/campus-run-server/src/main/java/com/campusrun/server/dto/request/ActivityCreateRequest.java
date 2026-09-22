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
