package com.campusrun.server.dto.request;

import jakarta.validation.constraints.NotNull;

public class SendFriendRequest {

    @NotNull(message = "目标用户不能为空")
    private Long targetUserId;

    public Long getTargetUserId() {
        return targetUserId;
    }

    public void setTargetUserId(Long targetUserId) {
        this.targetUserId = targetUserId;
    }
}
