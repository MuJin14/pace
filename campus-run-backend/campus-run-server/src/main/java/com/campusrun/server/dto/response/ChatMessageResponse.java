package com.campusrun.server.dto.response;

public class ChatMessageResponse {

    private Long messageId;
    private Long senderId;

    /**
     * 发送者昵称。
     *
     * <p><b>为什么消息里要带昵称（真实故障）</b>：客户端弹系统通知时需要
     * 「谁发的」。原先响应里只有 {@code senderId}，客户端只能去查好友列表，
     * 而**好友列表要等用户进过社区页才加载** —— 于是冷启动后收到的第一条消息，
     * 通知标题只能是「新消息」，用户看到通知但不知道是谁发的
     * （用户反馈的「首页的消息推送只能看到是未读消息，看不到具体是谁」）。
     *
     * <p>让服务端直接带上是最省事也最可靠的：发送者信息在服务端本来就有，
     * 且不受客户端缓存状态影响。
     *
     * <p>查不到时为 null，客户端回退到「新消息」——不会是空标题。
     */
    private String senderNickname;
    private Long receiverId;
    private String content;
    /** 消息类型：1=文本 2=图片 3=表情包。 */
    private Integer type;
    /** 媒体地址：type=2/3 时非空。 */
    private String mediaUrl;
    private Integer delivered;

    /** 已读时间（毫秒时间戳），null 表示接收方还未读。 */
    private Long readAt;

    private long timestamp;

    public Long getMessageId() {
        return messageId;
    }

    public void setMessageId(Long messageId) {
        this.messageId = messageId;
    }

    public Long getSenderId() {
        return senderId;
    }

    public void setSenderId(Long senderId) {
        this.senderId = senderId;
    }

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

    public Integer getDelivered() {
        return delivered;
    }

    public void setDelivered(Integer delivered) {
        this.delivered = delivered;
    }

    public Long getReadAt() {
        return readAt;
    }

    public void setReadAt(Long readAt) {
        this.readAt = readAt;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    public String getSenderNickname() {
        return senderNickname;
    }

    public void setSenderNickname(String senderNickname) {
        this.senderNickname = senderNickname;
    }
}
