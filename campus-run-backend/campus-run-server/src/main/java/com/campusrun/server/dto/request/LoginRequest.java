package com.campusrun.server.dto.request;

import jakarta.validation.constraints.NotBlank;

public class LoginRequest {

    @NotBlank(message = "手机号不能为空")
    private String phone;

    @NotBlank(message = "密码不能为空")
    private String password;

    /**
     * 设备标识（客户端生成的持久随机串）。
     *
     * <p>可选：老客户端不带这个字段时，服务端**不做设备判断**，
     * 退化成「每次登录都递增版本」—— 也就是「后登录的踢掉先登录的」。
     * 这是可以接受的降级：老客户端本来就没有被踢下线的处理逻辑，
     * 但它们会收到 401，用户重新登录即可。
     */
    private String deviceId;

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }
}
