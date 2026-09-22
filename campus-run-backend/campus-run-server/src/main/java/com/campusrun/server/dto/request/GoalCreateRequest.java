package com.campusrun.server.dto.request;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;

public class GoalCreateRequest {

    @NotBlank(message = "周期类型不能为空")
    private String periodType;

    @NotNull(message = "目标距离不能为空")
    @Min(value = 1, message = "目标距离不合法")
    private Integer targetDistanceMeters;

    @NotNull(message = "开始日期不能为空")
    private LocalDate startDate;

    @NotNull(message = "结束日期不能为空")
    private LocalDate endDate;

    public String getPeriodType() {
        return periodType;
    }

    public void setPeriodType(String periodType) {
        this.periodType = periodType;
    }

    public Integer getTargetDistanceMeters() {
        return targetDistanceMeters;
    }

    public void setTargetDistanceMeters(Integer targetDistanceMeters) {
        this.targetDistanceMeters = targetDistanceMeters;
    }

    public LocalDate getStartDate() {
        return startDate;
    }

    public void setStartDate(LocalDate startDate) {
        this.startDate = startDate;
    }

    public LocalDate getEndDate() {
        return endDate;
    }

    public void setEndDate(LocalDate endDate) {
        this.endDate = endDate;
    }
}
