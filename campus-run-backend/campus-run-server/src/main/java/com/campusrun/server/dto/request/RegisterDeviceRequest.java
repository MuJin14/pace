package com.campusrun.server.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** 登记设备推送令牌。 */
public class RegisterDeviceRequest {

    @NotBlank(message = "令牌不能为空")
    @Size(max = 255, message = "令牌过长")
    private String token;

    /** android / ios / web；为空时后端按 android 处理。 */
    @Size(max = 16)
    private String platform;

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }

    public String getPlatform() {
        return platform;
    }

    public void setPlatform(String platform) {
        this.platform = platform;
    }
}
