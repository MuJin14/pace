package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.Message;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

public interface MessageMapper extends BaseMapper<Message> {

    @Select("""
            SELECT * FROM message
            WHERE receiver_id = #{receiverId} AND delivered = 0
            ORDER BY id ASC
            LIMIT #{limit}
            """)
    List<Message> selectOffline(@Param("receiverId") long receiverId, @Param("limit") int limit);

    @Select("""
            SELECT * FROM message
            WHERE ((sender_id = #{me} AND receiver_id = #{friend})
                   OR (sender_id = #{friend} AND receiver_id = #{me}))
              AND id < #{beforeId}
            ORDER BY id DESC
            LIMIT #{size}
            """)
    List<Message> selectHistory(@Param("me") long me, @Param("friend") long friend,
                                @Param("beforeId") long beforeId, @Param("size") int size);
}
