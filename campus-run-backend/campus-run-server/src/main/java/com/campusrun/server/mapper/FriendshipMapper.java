package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.FriendRequestResponse;
import com.campusrun.server.dto.response.UserBriefResponse;
import com.campusrun.server.entity.Friendship;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

public interface FriendshipMapper extends BaseMapper<Friendship> {

    @Select("""
            SELECT u.id AS userId, u.unique_id AS uniqueId, u.nickname AS nickname, u.avatar_url AS avatarUrl
            FROM user u
            WHERE u.id != #{me}
              AND (u.unique_id LIKE CONCAT('%', #{kw}, '%')
                   OR u.nickname LIKE CONCAT('%', #{kw}, '%')
                   OR u.phone LIKE CONCAT('%', #{kw}, '%'))
              AND u.id NOT IN (
                  SELECT friend_id FROM friendship WHERE user_id = #{me} AND status = 1
              )
            ORDER BY u.id
            LIMIT #{size} OFFSET #{offset}
            """)
    List<UserBriefResponse> searchUsers(@Param("me") long me, @Param("kw") String kw,
                                        @Param("offset") long offset, @Param("size") long size);

    @Select("""
            SELECT COUNT(*)
            FROM user u
            WHERE u.id != #{me}
              AND (u.unique_id LIKE CONCAT('%', #{kw}, '%')
                   OR u.nickname LIKE CONCAT('%', #{kw}, '%')
                   OR u.phone LIKE CONCAT('%', #{kw}, '%'))
              AND u.id NOT IN (
                  SELECT friend_id FROM friendship WHERE user_id = #{me} AND status = 1
              )
            """)
    long countSearch(@Param("me") long me, @Param("kw") String kw);

    @Select("""
            SELECT f.id AS friendshipId, u.id AS userId, u.unique_id AS uniqueId,
                   u.nickname AS nickname, u.avatar_url AS avatarUrl, f.created_at AS createdAt
            FROM friendship f
            JOIN user u ON u.id = f.friend_id
            WHERE f.user_id = #{me} AND f.status = 1
            ORDER BY f.id DESC
            """)
    List<FriendItemResponse> selectFriends(@Param("me") long me);

    @Select("""
            SELECT f.id AS requestId, u.id AS userId, u.unique_id AS uniqueId,
                   u.nickname AS nickname, u.avatar_url AS avatarUrl, f.created_at AS createdAt
            FROM friendship f
            JOIN user u ON u.id = f.user_id
            WHERE f.friend_id = #{me} AND f.status = 0
            ORDER BY f.id DESC
            """)
    List<FriendRequestResponse> selectIncoming(@Param("me") long me);
}
