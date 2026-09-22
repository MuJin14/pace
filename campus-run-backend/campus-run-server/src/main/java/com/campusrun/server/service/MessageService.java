package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.ChatMessageResponse;

public interface MessageService {

    /**
     * 发送消息：落库后若对方在线则推送，否则留作离线消息。
     *
     * @param senderId   发送方用户 ID
     * @param receiverId 接收方用户 ID
     * @param content    消息内容
     * @return 消息体（含投递状态）
     * @throws BusinessException 内容为空或超长、对方不是好友
     */
    ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content);

    /**
     * 将用户的离线消息逐批推送，成功后标记已投递。
     *
     * @param userId 接收方用户 ID
     */
    void pushOfflineMessages(Long userId);

    /**
     * 分页查询与某好友的聊天记录，按时间倒序。
     *
     * @param userId   当前用户 ID
     * @param friendId 好友用户 ID
     * @param beforeId 游标消息 ID，返回该 ID 之前的消息，可为 null 表示最新
     * @param size     条数
     * @return 聊天记录分页列表
     */
    PageResponse<ChatMessageResponse> history(Long userId, Long friendId, Long beforeId, long size);
}
