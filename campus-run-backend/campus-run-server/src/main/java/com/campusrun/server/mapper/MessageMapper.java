package com.campusrun.server.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campusrun.server.entity.Message;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

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

    /**
     * 全部仍在被引用的媒体 URL。
     *
     * <p>保留策略用它来判断「这个文件还有没有人要」。
     * 只取非空值：media_url 已经过期的消息不该继续「保护」它的文件。
     */
    @Select("""
            SELECT media_url FROM message
            WHERE media_url IS NOT NULL AND media_url <> ''
            """)
    List<String> selectReferencedMediaUrls();

    /**
     * 把超过保留期的图片/表情消息的 media_url 置空。
     *
     * <p><b>只清 media_url，不删消息</b>：直接删行会让聊天记录凭空少几条，
     * 用户会以为丢数据。置空后前端显示「图片已过期」，
     * 对话结构保持完整。
     *
     * <p>用 `created_at` 判断而不是文件 mtime：文件可能被重新写入
     * （比如重传同名文件），而「这条消息多久了」才是业务上的过期依据。
     *
     * @param days 保留天数
     * @return 受影响行数
     */
    @Update("""
            UPDATE message SET media_url = NULL
            WHERE media_url IS NOT NULL AND media_url <> ''
              AND type IN (2, 3)
              AND created_at < DATE_SUB(NOW(), INTERVAL #{days} DAY)
            """)
    int clearExpiredMediaUrls(@Param("days") int days);

    /**
     * 按发送方统计当前用户的未读消息数。
     *
     * <p><b>为什么必须有这个查询（真实故障）</b>：客户端的未读红点原本是
     * **纯内存态** —— 只有 WebSocket 实时到达的消息才会 +1。于是：
     * 设备离线（或被顶下线）期间收到的消息，登录后**完全没有红点提示**，
     * 用户不知道有人给自己发过消息。
     *
     * <p>读状态用 {@code read_at IS NULL} 判断（不是布尔字段）：这样
     * 「读过的时刻」本身也是数据，将来要做「已读回执」不用再加列。
     *
     * <p>返回 [{sender_id, cnt}]，由 Service 转成 Map。
     */
    @Select("""
            SELECT sender_id AS senderId, COUNT(*) AS cnt
            FROM message
            WHERE receiver_id = #{receiverId}
              AND read_at IS NULL
            GROUP BY sender_id
            """)
    List<java.util.Map<String, Object>> countUnreadBySender(
            @Param("receiverId") long receiverId);
}
