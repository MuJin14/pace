package com.campusrun.server.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

import java.time.LocalDateTime;

/**
 * 设备推送令牌。
 *
 * <p>一个用户可能有多个设备（手机 + 平板 + 浏览器），所以是 1:N，
 * 推送时要给该用户的**所有**令牌各发一次。
 *
 * <p>{@code token} 上有唯一索引：FCM 令牌会在重装/清数据后重新分配，
 * 同一个令牌可能先属于 A 又变为 B 的设备，注册时必须按令牌 upsert 改写归属，
 * 否则通知会推给错误的人。
 */
@TableName("device_token")
public class DeviceToken {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long userId;

    /** FCM 注册令牌（Android/iOS/Web 通用）。 */
    private String token;

    /** 平台：android / ios / web。用于选择合适的推送通道与文案。 */
    private String platform;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

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

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
