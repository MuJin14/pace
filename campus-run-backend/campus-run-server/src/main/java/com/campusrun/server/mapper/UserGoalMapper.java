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

    // ── 历史数据修复用：按 activity 重算目标进度 ──────────────────────
    //
    // 目标进度是「累加」出来的（addProgress 用 current + distance），
    // 一旦某次运动的距离算错，进度就永久偏小且无法自愈。
    // 这里按「目标周期区间内的有效运动距离之和」重算，
    // 区间语义与 addProgress 的 [startDate, endDate] 完全一致。

    @Update("""
            UPDATE user_goal g
            SET g.current_distance_meters = COALESCE((
                    SELECT SUM(a.distance_meters) FROM activity a
                    WHERE a.user_id = g.user_id AND a.invalid = 0
                      AND DATE(a.start_time) >= g.start_date
                      AND DATE(a.start_time) <= g.end_date), 0),
                g.updated_at = CURRENT_TIMESTAMP
            WHERE g.id = #{goalId}
            """)
    int recomputeProgress(@Param("goalId") long goalId);

    @Select("SELECT id FROM user_goal")
    List<Long> selectAllGoalIds();
}
