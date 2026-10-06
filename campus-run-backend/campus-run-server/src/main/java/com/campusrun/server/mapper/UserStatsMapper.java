package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.UserStats;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDate;
import java.util.List;

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

    // ── 历史数据修复用：按 activity 全量重算累计里程与次数 ──────────────
    //
    // 只重算「能推导得出」的两个字段（累计里程、累计次数），
    // **刻意不碰** weekly_goal_completed_count：那是「完成周目标」这一过程的
    // 结果，无法从 activity 反推，重算会把用户已获得的成绩抹掉。

    @Update("""
            UPDATE user_stats us
            SET us.total_distance_meters = COALESCE((
                    SELECT SUM(a.distance_meters) FROM activity a
                    WHERE a.user_id = us.user_id AND a.invalid = 0), 0),
                us.total_activity_count = COALESCE((
                    SELECT COUNT(*) FROM activity a
                    WHERE a.user_id = us.user_id AND a.invalid = 0), 0),
                us.updated_at = CURRENT_TIMESTAMP
            """)
    int recomputeTotals();

    /** 累计里程/次数为 0、但库里其实有有效记录的用户（修复前的脏数据）。 */
    @Select("""
            SELECT us.user_id FROM user_stats us
            WHERE EXISTS (SELECT 1 FROM activity a
                          WHERE a.user_id = us.user_id AND a.invalid = 0 AND a.distance_meters > 0)
              AND (us.total_distance_meters = 0 OR us.total_activity_count = 0)
            """)
    List<Long> selectUsersWithStaleTotals();

    /** 某用户全部「有效运动」的日期（新→旧），用于重算连续打卡天数。 */
    @Select("""
            SELECT DISTINCT DATE(start_time) AS d FROM activity
            WHERE user_id = #{userId} AND invalid = 0
            ORDER BY d DESC
            """)
    List<LocalDate> selectActivityDates(@Param("userId") long userId);

    @Update("""
            UPDATE user_stats
            SET streak_days = #{streakDays},
                last_activity_date = #{lastDate},
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = #{userId}
            """)
    int updateStreak(@Param("userId") long userId,
                     @Param("streakDays") int streakDays,
                     @Param("lastDate") LocalDate lastDate);
}
