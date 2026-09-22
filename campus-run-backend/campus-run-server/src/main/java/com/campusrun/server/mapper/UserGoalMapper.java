package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.UserGoal;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDate;
import java.util.List;

public interface UserGoalMapper extends BaseMapper<UserGoal> {

    @Update("""
            UPDATE user_goal
            SET current_distance_meters = current_distance_meters + #{distance},
                updated_at = CURRENT_TIMESTAMP
            WHERE id = #{goalId} AND status = 0
            """)
    int addProgress(@Param("goalId") long goalId, @Param("distance") int distance);

    @Select("SELECT * FROM user_goal WHERE period_type = 'weekly' AND status = 0 AND end_date < #{today}")
    List<UserGoal> selectEndedWeeklyGoals(@Param("today") LocalDate today);
}
