package com.campusrun.server.dto.websocket;

import java.util.List;

/**
 * type = "read_receipt" 的推送数据（服务端 → 客户端）。
 *
 * 语义：接收方 {@code readerId} 读取了与好友 {@code friendId} 的会话，
 * 本次把 {@code messageIds} 这些「好友发给接收方」的消息标记为已读，标记时间为 {@code readAt}（毫秒时间戳）。
 * 该回执推送给会话对端（即原发送者 friendId），用于把发送方的气泡渲染成「已读」。
 */
public class ReadReceiptPushData {

    /** WebSocket 信封 type 取值。 */
    public static final String TYPE = "read_receipt";

    private Long readerId;
    private Long friendId;
    private List<Long> messageIds;
    private long readAt;

    public ReadReceiptPushData() {
    }

    public ReadReceiptPushData(Long readerId, Long friendId, List<Long> messageIds, long readAt) {
        this.readerId = readerId;
        this.friendId = friendId;
        this.messageIds = messageIds;
        this.readAt = readAt;
    }

    public Long getReaderId() {
        return readerId;
    }

    public void setReaderId(Long readerId) {
        this.readerId = readerId;
    }

    public Long getFriendId() {
        return friendId;
    }

    public void setFriendId(Long friendId) {
        this.friendId = friendId;
    }

    public List<Long> getMessageIds() {
        return messageIds;
    }

    public void setMessageIds(List<Long> messageIds) {
        this.messageIds = messageIds;
    }

    public long getReadAt() {
        return readAt;
    }

    public void setReadAt(long readAt) {
        this.readAt = readAt;
    }
}
