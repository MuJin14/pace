package com.campusrun.server.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

import java.time.LocalDateTime;

/**
 * 密码重置申请。
 *
 * <p><b>为什么需要这张表</b>：App 没有邮箱字段、也没有短信服务，用户忘记密码后
 * 只能线下找人帮忙。有了这张表，用户可以在 App 里自助提交申请，
 * 管理员在后台<b>看得到</b>谁需要帮助——而不是等人来喊。
 *
 * <p>状态流转：待处理(0) → 已重置(1) / 已拒绝(2)，单向不可逆。
 * 处理时记录 [handledBy] 与 [handledAt]，便于追溯（管理员操作要留痕）。
 */
@TableName("password_reset_request")
public class PasswordResetRequest {

    /** 待处理。 */
    public static final int STATUS_PENDING = 0;
    /** 已由管理员重置密码。 */
    public static final int STATUS_RESET = 1;
    /** 已拒绝（例如申请人与账号信息不符）。 */
    public static final int STATUS_REJECTED = 2;

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long userId;

    /** 冗余存手机号与昵称：用户注销后申请记录仍可追溯，不必依赖 user 表还在。 */
    private String phone;

    private String nickname;

    private Integer status;

    /** 申请人填写的情况说明（可选，例如「换手机了登不上」）。 */
    private String note;

    private Long handledBy;

    private LocalDateTime handledAt;

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

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public Integer getStatus() {
        return status;
    }

    public void setStatus(Integer status) {
        this.status = status;
    }

    public String getNote() {
        return note;
    }

    public void setNote(String note) {
        this.note = note;
    }

    public Long getHandledBy() {
        return handledBy;
    }

    public void setHandledBy(Long handledBy) {
        this.handledBy = handledBy;
    }

    public LocalDateTime getHandledAt() {
        return handledAt;
    }

    public void setHandledAt(LocalDateTime handledAt) {
        this.handledAt = handledAt;
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
