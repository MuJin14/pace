package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.ChatPreference;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

@Mapper
public interface ChatPreferenceMapper extends BaseMapper<ChatPreference> {

    /**
     * 查询某用户所有「免打扰」的会话对方 id。
     *
     * <p>只取 muted=1 的行：前端拿到的就是一份「静音名单」，
     * 不需要把全部会话偏好传下去再自己过滤。
     */
    @Select("""
            SELECT friend_id FROM chat_preference
            WHERE user_id = #{userId} AND muted = 1
            """)
    List<Long> selectMutedFriendIds(@Param("userId") long userId);

    /**
     * 注销账号时清理该用户的会话偏好。
     *
     * <p>两个方向都要删：自己设的偏好（{@code user_id}），
     * 以及**别人对我设的**偏好（{@code friend_id}）。
     * 只删 user_id 会留下「指向已注销用户」的孤儿行 ——
     * 虽然现有查询都带 user_id 过滤、不会泄漏给谁，
     * 但孤儿数据会让「注销会把数据删干净」这个合规承诺打折扣。
     */
    @Delete("DELETE FROM chat_preference WHERE user_id = #{userId} OR friend_id = #{userId}")
    int deleteByUser(@Param("userId") Long userId);
}
