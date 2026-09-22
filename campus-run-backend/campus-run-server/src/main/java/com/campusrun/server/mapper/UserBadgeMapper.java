package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.UserBadge;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;

public interface UserBadgeMapper extends BaseMapper<UserBadge> {

    @Insert("INSERT IGNORE INTO user_badge (user_id, badge_id) VALUES (#{userId}, #{badgeId})")
    int insertIgnore(@Param("userId") long userId, @Param("badgeId") long badgeId);
}
