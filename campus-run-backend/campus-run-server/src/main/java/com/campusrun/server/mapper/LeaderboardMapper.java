package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.entity.LeaderboardStat;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDateTime;
import java.util.List;

public interface LeaderboardMapper extends BaseMapper<LeaderboardStat> {

    @Insert("""
            INSERT INTO leaderboard_stats (user_id, scope, period, type, distance_meters)
            VALUES (#{userId}, #{scope}, #{period}, #{type}, #{distance})
            ON DUPLICATE KEY UPDATE distance_meters = distance_meters + #{distance},
                                    updated_at = CURRENT_TIMESTAMP
            """)
    int upsertDistance(@Param("userId") long userId,
                       @Param("scope") String scope,
                       @Param("period") String period,
                       @Param("type") int type,
                       @Param("distance") int distance);

    @Select("SELECT COUNT(*) FROM leaderboard_stats WHERE scope = #{scope} AND period = #{period} AND type = #{type}")
    long countBoard(@Param("scope") String scope, @Param("period") String period, @Param("type") int type);

    @Select("""
            SELECT ls.user_id AS userId, u.unique_id AS uniqueId, u.nickname AS nickname,
                   u.avatar_url AS avatarUrl, ls.distance_meters AS distanceMeters
            FROM leaderboard_stats ls
            JOIN user u ON u.id = ls.user_id
            WHERE ls.scope = #{scope} AND ls.period = #{period} AND ls.type = #{type}
            ORDER BY ls.distance_meters DESC, ls.user_id ASC
            LIMIT #{size} OFFSET #{offset}
            """)
    List<LeaderboardEntryResponse> selectBoardPage(@Param("scope") String scope,
                                                   @Param("period") String period,
                                                   @Param("type") int type,
                                                   @Param("offset") long offset,
                                                   @Param("size") long size);

    @Select("""
            SELECT distance_meters FROM leaderboard_stats
            WHERE scope = #{scope} AND period = #{period} AND type = #{type} AND user_id = #{userId}
            """)
    Integer selectDistance(@Param("scope") String scope,
                           @Param("period") String period,
                           @Param("type") int type,
                           @Param("userId") long userId);

    @Select("""
            SELECT COUNT(*) FROM leaderboard_stats
            WHERE scope = #{scope} AND period = #{period} AND type = #{type} AND distance_meters > #{distance}
            """)
    long countGreaterThan(@Param("scope") String scope,
                          @Param("period") String period,
                          @Param("type") int type,
                          @Param("distance") int distance);

    @Delete("DELETE FROM leaderboard_stats WHERE scope = 'rolling30d' AND type = #{type}")
    int deleteRolling30d(@Param("type") int type);

    @Insert("""
            INSERT INTO leaderboard_stats (user_id, scope, period, type, distance_meters)
            SELECT user_id, 'rolling30d', 'CURRENT', #{type}, SUM(distance_meters)
            FROM activity
            WHERE start_time >= #{cutoff} AND type = #{type}
            GROUP BY user_id
            """)
    int insertRolling30d(@Param("type") int type, @Param("cutoff") LocalDateTime cutoff);

    @Delete("DELETE FROM leaderboard_stats WHERE scope = #{scope} AND type = #{type} AND period < #{beforePeriod}")
    int deleteExpired(@Param("scope") String scope, @Param("type") int type, @Param("beforePeriod") String beforePeriod);
}
