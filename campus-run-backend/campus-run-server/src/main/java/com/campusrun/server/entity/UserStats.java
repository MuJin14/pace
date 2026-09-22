package com.campusrun.server.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

import java.time.LocalDate;
import java.time.LocalDateTime;

@TableName("user_stats")
public class UserStats {

    @TableId(type = IdType.INPUT)
    private Long userId;

    private Integer totalDistanceMeters;
    private Integer totalActivityCount;
    private Integer streakDays;
    private LocalDate lastActivityDate;
    private Integer weeklyGoalCompletedCount;
    private LocalDateTime updatedAt;

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public Integer getTotalDistanceMeters() {
        return totalDistanceMeters;
    }

    public void setTotalDistanceMeters(Integer totalDistanceMeters) {
        this.totalDistanceMeters = totalDistanceMeters;
    }

    public Integer getTotalActivityCount() {
        return totalActivityCount;
    }

    public void setTotalActivityCount(Integer totalActivityCount) {
        this.totalActivityCount = totalActivityCount;
    }

    public Integer getStreakDays() {
        return streakDays;
    }

    public void setStreakDays(Integer streakDays) {
        this.streakDays = streakDays;
    }

    public LocalDate getLastActivityDate() {
        return lastActivityDate;
    }

    public void setLastActivityDate(LocalDate lastActivityDate) {
        this.lastActivityDate = lastActivityDate;
    }

    public Integer getWeeklyGoalCompletedCount() {
        return weeklyGoalCompletedCount;
    }

    public void setWeeklyGoalCompletedCount(Integer weeklyGoalCompletedCount) {
        this.weeklyGoalCompletedCount = weeklyGoalCompletedCount;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
