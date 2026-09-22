package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.UserStats;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDate;

public interface UserStatsMapper extends BaseMapper<UserStats> {

    @Update("""
            UPDATE user_stats
            SET streak_days = 0
            WHERE last_activity_date IS NOT NULL AND last_activity_date < #{beforeDate}
            """)
    int resetStreaks(@Param("beforeDate") LocalDate beforeDate);

    @Insert("""
            INSERT INTO user_stats (user_id, weekly_goal_completed_count)
            VALUES (#{userId}, 1)
            ON DUPLICATE KEY UPDATE weekly_goal_completed_count = weekly_goal_completed_count + 1
            """)
    int incrementWeeklyGoalCompleted(@Param("userId") long userId);
}
