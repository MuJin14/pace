package com.campusrun.server.dto.response;

import com.campusrun.server.model.TrackPoint;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public class ActivityDetailResponse {

    private Long activityId;
    private Integer type;
    private Integer distanceMeters;
    private Integer durationSeconds;
    private BigDecimal avgSpeed;
    private Integer avgPace;
    private BigDecimal calories;
    private LocalDateTime startTime;
    private LocalDateTime endTime;
    private LocalDateTime createdAt;
    private List<TrackPoint> track;

    public Long getActivityId() {
        return activityId;
    }

    public void setActivityId(Long activityId) {
        this.activityId = activityId;
    }

    public Integer getType() {
        return type;
    }

    public void setType(Integer type) {
        this.type = type;
    }

    public Integer getDistanceMeters() {
        return distanceMeters;
    }

    public void setDistanceMeters(Integer distanceMeters) {
        this.distanceMeters = distanceMeters;
    }

    public Integer getDurationSeconds() {
        return durationSeconds;
    }

    public void setDurationSeconds(Integer durationSeconds) {
        this.durationSeconds = durationSeconds;
    }

    public BigDecimal getAvgSpeed() {
        return avgSpeed;
    }

    public void setAvgSpeed(BigDecimal avgSpeed) {
        this.avgSpeed = avgSpeed;
    }

    public Integer getAvgPace() {
        return avgPace;
    }

    public void setAvgPace(Integer avgPace) {
        this.avgPace = avgPace;
    }

    public BigDecimal getCalories() {
        return calories;
    }

    public void setCalories(BigDecimal calories) {
        this.calories = calories;
    }

    public LocalDateTime getStartTime() {
        return startTime;
    }

    public void setStartTime(LocalDateTime startTime) {
        this.startTime = startTime;
    }

    public LocalDateTime getEndTime() {
        return endTime;
    }

    public void setEndTime(LocalDateTime endTime) {
        this.endTime = endTime;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public List<TrackPoint> getTrack() {
        return track;
    }

    public void setTrack(List<TrackPoint> track) {
        this.track = track;
    }
}
