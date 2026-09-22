package com.campusrun.server.dto.request;

import jakarta.validation.constraints.NotNull;

public class AcceptFriendRequest {

    @NotNull(message = "申请ID不能为空")
    private Long requestId;

    public Long getRequestId() {
        return requestId;
    }

    public void setRequestId(Long requestId) {
        this.requestId = requestId;
    }
}
