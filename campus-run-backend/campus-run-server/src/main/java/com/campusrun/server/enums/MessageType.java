package com.campusrun.server.enums;

/**
 * 消息类型。
 *
 * <p>用枚举而不是裸 int：类型判断散落在 service / 前端 / 推送正文里，
 * 裸字面量很容易写成「1 是图片还是文本」这类低级错误。
 */
public enum MessageType {

    /** 纯文本，content 非空。 */
    TEXT(1),

    /** 图片，mediaUrl 必填。 */
    IMAGE(2),

    /** 表情包（内置贴图），mediaUrl 指向贴图资源。 */
    STICKER(3);

    private final int code;

    MessageType(int code) {
        this.code = code;
    }

    public int getCode() {
        return code;
    }

    /** 未知类型返回 null，由调用方决定是报错还是兜底成文本。 */
    public static MessageType fromCode(Integer code) {
        if (code == null) {
            return null;
        }
        for (MessageType type : values()) {
            if (type.code == code) {
                return type;
            }
        }
        return null;
    }

    /** 是否属于「必须带 mediaUrl」的类型。 */
    public boolean requiresMedia() {
        return this == IMAGE || this == STICKER;
    }
}
