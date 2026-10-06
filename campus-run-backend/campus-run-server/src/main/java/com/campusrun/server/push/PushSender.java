package com.campusrun.server.push;

import java.util.Map;

/**
 * 推送发送器抽象。
 *
 * <p>抽成接口有两个目的：
 * <ol>
 *   <li>**没有 FireBase 凭证也能跑通并测试**：默认用 {@link LoggingPushSender}
 *       把「本该推送的内容」写进日志，业务链路与测试全部可验证；</li>
 *   <li>将来换通道（APNs 直连、厂商推送、极光等）只换实现，不动业务代码。</li>
 * </ol>
 */
public interface PushSender {

    /**
     * 发送一条推送。
     *
     * @param token 设备令牌
     * @param title 通知标题
     * @param body  通知正文
     * @param data  附加数据（客户端点击通知后据此跳转），键值都必须是字符串
     * @return 推送结果；**令牌失效**时返回 {@link Result#INVALID_TOKEN}，
     *         调用方应据此删除该令牌，避免每次都白推一遍
     */
    Result send(String token, String title, String body, Map<String, String> data);

    /** 是否已配置真实凭证。未配置时上层可选择跳过而不必每次尝试。 */
    default boolean isConfigured() {
        return false;
    }

    enum Result {
        /** 推送已交给推送服务。 */
        SUCCESS,
        /** 令牌失效或已注销，应删除。 */
        INVALID_TOKEN,
        /** 临时失败（网络、限流、服务端 5xx），可重试，不要删令牌。 */
        RETRYABLE_FAILURE,
        /** 未配置凭证，未真实发送。 */
        NOT_CONFIGURED
    }
}
