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

    /**
     * 搜索用户。
     *
     * <p>**故意不再排除自己和已有好友**：产品要的是微信式社交——搜到自己可以看自己的主页，
     * 搜到好友可以直接进去聊天。因此这里只做关键词匹配，「要不要显示、显示成什么操作」
     * 交给上层按 {@code UserRelation} 决定。
     */
    @Select("""
            SELECT u.id AS userId, u.unique_id AS uniqueId, u.nickname AS nickname, u.avatar_url AS avatarUrl
            FROM user u
            WHERE (u.unique_id LIKE CONCAT('%', #{kw}, '%')
                   OR u.nickname LIKE CONCAT('%', #{kw}, '%')
                   OR u.phone LIKE CONCAT('%', #{kw}, '%'))
            ORDER BY u.id
            LIMIT #{size} OFFSET #{offset}
            """)
    List<UserBriefResponse> searchUsers(@Param("me") long me, @Param("kw") String kw,
                                        @Param("offset") long offset, @Param("size") long size);

    @Select("""
            SELECT COUNT(*)
            FROM user u
            WHERE (u.unique_id LIKE CONCAT('%', #{kw}, '%')
                   OR u.nickname LIKE CONCAT('%', #{kw}, '%')
                   OR u.phone LIKE CONCAT('%', #{kw}, '%'))
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

    /**
     * 当前用户**已接受**的好友 id 列表。
     *
     * <p>未读计数接口用它拼出完整快照（所有好友都在响应里，未读为 0 给 0），
     * 客户端才能据此清掉已经读过的红点。
     */
    @Select("""
            SELECT friend_id FROM friendship
            WHERE user_id = #{userId} AND status = 1
            """)
    List<Long> selectAcceptedFriendIds(@Param("userId") long userId);
}
