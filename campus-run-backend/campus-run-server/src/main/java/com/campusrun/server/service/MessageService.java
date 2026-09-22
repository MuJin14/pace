package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.ChatMessageResponse;

public interface MessageService {

    ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content);

    void pushOfflineMessages(Long userId);

    PageResponse<ChatMessageResponse> history(Long userId, Long friendId, Long beforeId, long size);
}
