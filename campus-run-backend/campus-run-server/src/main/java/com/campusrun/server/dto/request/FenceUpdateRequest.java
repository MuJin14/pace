package com.campusrun.server.dto.request;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

public class FenceUpdateRequest {

    @NotBlank(message = "围栏名称不能为空")
    @Size(max = 50, message = "围栏名称过长")
    private String name;

    @NotNull(message = "中心纬度不能为空")
    @DecimalMin(value = "-90.0", message = "纬度不合法")
    @DecimalMax(value = "90.0", message = "纬度不合法")
    private BigDecimal centerLat;

    @NotNull(message = "中心经度不能为空")
    @DecimalMin(value = "-180.0", message = "经度不合法")
    @DecimalMax(value = "180.0", message = "经度不合法")
    private BigDecimal centerLng;

    @NotNull(message = "半径不能为空")
    @Min(value = 1, message = "半径不合法")
    private Integer radiusMeters;

    @DecimalMin(value = "0.0", message = "允许比例不合法")
    @DecimalMax(value = "1.0", message = "允许比例不合法")
    private BigDecimal allowedOutsideRatio;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public BigDecimal getCenterLat() {
        return centerLat;
    }

    public void setCenterLat(BigDecimal centerLat) {
        this.centerLat = centerLat;
    }

    public BigDecimal getCenterLng() {
        return centerLng;
    }

    public void setCenterLng(BigDecimal centerLng) {
        this.centerLng = centerLng;
    }

    public Integer getRadiusMeters() {
        return radiusMeters;
    }

    public void setRadiusMeters(Integer radiusMeters) {
        this.radiusMeters = radiusMeters;
    }

    public BigDecimal getAllowedOutsideRatio() {
        return allowedOutsideRatio;
    }

    public void setAllowedOutsideRatio(BigDecimal allowedOutsideRatio) {
        this.allowedOutsideRatio = allowedOutsideRatio;
    }
}
