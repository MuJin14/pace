package com.campusrun.server.enums;

/**
 * 当前登录用户与某个目标用户的关系。
 *
 * <p>为什么要在接口里明确返回它：客户端要据此决定按钮是「发消息」「添加好友」
 * 还是「通过验证」。让服务端算一次，而不是让前端自己拼好友列表 + 申请列表去推断，
 * 可以避免两边规则不一致（例如前端漏算「对方已申请我」的情况，导致本该显示
 * 「通过验证」却显示「添加」）。
 */
public enum UserRelation {

    /** 就是自己。 */
    SELF("self"),

    /** 已是好友，可直接聊天。 */
    FRIEND("friend"),

    /** 我已向对方发出申请，等待对方处理。 */
    PENDING_OUTGOING("pending_outgoing"),

    /** 对方已向我发出申请，我可以直接通过。 */
    PENDING_INCOMING("pending_incoming"),

    /** 无关系。 */
    NONE("none");

    private final String code;

    UserRelation(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
