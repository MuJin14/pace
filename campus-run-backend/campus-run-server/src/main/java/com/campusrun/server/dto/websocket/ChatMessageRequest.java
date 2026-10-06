package com.campusrun.server.dto.websocket;

/**
 * WebSocket 发消息请求体。
 *
 * <p>{@code type} 缺省按 1（文本）处理，保持与旧客户端兼容 ——
 * 老版本 App 只传 receiverId + content，不应因为服务端加了富媒体就发不出消息。
 */
public class ChatMessageRequest {

    private Long receiverId;
    private String content;

    /** 消息类型：1=文本 2=图片 3=表情包；不传按 1 处理。 */
    private Integer type;

    /** 媒体地址：type=2/3 时必填。 */
    private String mediaUrl;

    public Long getReceiverId() {
        return receiverId;
    }

    public void setReceiverId(Long receiverId) {
        this.receiverId = receiverId;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Integer getType() {
        return type;
    }

    public void setType(Integer type) {
        this.type = type;
    }

    public String getMediaUrl() {
        return mediaUrl;
    }

    public void setMediaUrl(String mediaUrl) {
        this.mediaUrl = mediaUrl;
    }
}
