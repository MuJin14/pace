package com.campusrun.common.result;

public enum ErrorCode {
    SUCCESS(0, "成功"),
    PARAM_ERROR(400, "参数错误"),
    UNAUTHORIZED(401, "未认证或登录已过期"),
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
