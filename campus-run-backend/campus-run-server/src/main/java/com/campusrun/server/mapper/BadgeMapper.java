package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.Badge;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

public interface BadgeMapper extends BaseMapper<Badge> {

    @Select("""
            SELECT * FROM badge
            WHERE enabled = 1 AND (
                (rule_type = 'total_distance' AND rule_value <= #{totalDistance}) OR
                (rule_type = 'activity_count' AND rule_value <= #{activityCount}) OR
                (rule_type = 'streak_days' AND rule_value <= #{streakDays}) OR
                (rule_type = 'weekly_goal_complete' AND rule_value <= #{weeklyGoalCompleted})
            )
            ORDER BY sort ASC, id ASC
            """)
    List<Badge> selectEligible(@Param("totalDistance") int totalDistance,
                               @Param("activityCount") int activityCount,
                               @Param("streakDays") int streakDays,
                               @Param("weeklyGoalCompleted") int weeklyGoalCompleted);
}
