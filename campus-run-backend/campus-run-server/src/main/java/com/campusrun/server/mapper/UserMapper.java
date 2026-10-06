package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.User;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface UserMapper extends BaseMapper<User> {

    @Select("SELECT id FROM user WHERE id = #{userId} FOR UPDATE")
    Long lockUserForUpdate(@Param("userId") Long userId);

    // ── 账号注销：级联清理该用户的全部数据 ──────────────────────────
    // 用显式 @Delete 而非外键 ON DELETE CASCADE：本项目测试库与生产库都未声明外键，
    // 显式删除能让「注销会删掉哪些数据」在代码里一目了然，并可被单测逐条覆盖。

    @Delete("DELETE FROM activity WHERE user_id = #{userId}")
    int deleteActivities(@Param("userId") Long userId);

    @Delete("DELETE FROM friendship WHERE user_id = #{userId} OR friend_id = #{userId}")
    int deleteFriendships(@Param("userId") Long userId);

    @Delete("DELETE FROM message WHERE sender_id = #{userId} OR receiver_id = #{userId}")
    int deleteMessages(@Param("userId") Long userId);

    @Delete("DELETE FROM leaderboard_stats WHERE user_id = #{userId}")
    int deleteLeaderboardStats(@Param("userId") Long userId);

    @Delete("DELETE FROM user_goal WHERE user_id = #{userId}")
    int deleteGoals(@Param("userId") Long userId);

    @Delete("DELETE FROM user_badge WHERE user_id = #{userId}")
    int deleteUserBadges(@Param("userId") Long userId);

    @Delete("DELETE FROM user_stats WHERE user_id = #{userId}")
    int deleteUserStats(@Param("userId") Long userId);
}
