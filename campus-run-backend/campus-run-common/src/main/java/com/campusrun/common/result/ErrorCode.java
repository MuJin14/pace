package com.campusrun.common.result;

public enum ErrorCode {
    SUCCESS(0, "成功"),
    PARAM_ERROR(400, "参数错误"),
    UNAUTHORIZED(401, "未认证或登录已过期"),

    /**
     * 账号已在**另一台设备**上登录，本设备的登录状态已被顶掉。
     *
     * <p>与 {@link #UNAUTHORIZED} 分开是必要的：客户端收到 401 的默认反应是
     * 「尝试刷新令牌」，而这里刷新也没用（版本已变），
     * 必须直接回登录页并告诉用户原因 —— 否则用户只会看到
     * 「登录已过期」然后反复重试。
     */
    SESSION_REPLACED(4011, "账号已在其他设备登录，请重新登录"),
    FORBIDDEN(403, "无权限"),
    NOT_FOUND(404, "请求的资源不存在"),
    TOO_MANY_REQUESTS(429, "操作过于频繁，请稍后再试"),
    INVALID_REFRESH_TOKEN(1004, "刷新令牌无效或已过期"),
    PHONE_EXISTS(1001, "手机号已注册"),
    USER_NOT_FOUND(1002, "用户不存在"),
    PASSWORD_ERROR(1003, "密码错误"),
    ACTIVITY_NOT_FOUND(2001, "运动记录不存在"),
    ACTIVITY_FORBIDDEN(2002, "无权访问该运动记录"),
    FRIEND_REQUEST_EXISTS(3001, "好友申请已存在或已是好友"),
    FRIEND_REQUEST_NOT_FOUND(3002, "好友申请不存在"),
    CANNOT_FRIEND_SELF(3003, "不能添加自己为好友"),
    FRIEND_NOT_FOUND(3004, "对方不是你的好友"),
    MESSAGE_CONTENT_INVALID(4001, "消息内容为空或超长"),
    FENCE_NOT_FOUND(5001, "围栏不存在"),
    GOAL_EXISTS(5002, "同周期目标已存在"),
    GOAL_NOT_FOUND(5003, "目标不存在"),
    GOAL_INVALID(5004, "目标不可操作"),
    FILE_INVALID(6001, "文件为空或格式不受支持"),
    FILE_TOO_LARGE(6002, "文件超过大小限制"),
    FILE_SAVE_ERROR(6003, "文件保存失败"),
    INTERNAL_ERROR(500, "服务器内部错误");

    private final int code;
    private final String message;

    ErrorCode(int code, String message) {
        this.code = code;
        this.message = message;
    }

    public int getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }
}
